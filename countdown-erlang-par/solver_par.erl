%% Work out the simplest Countdown expression that hits a target or gets closest to it sharing the largest searches across worker processes
-module(solver_par).
-export([solve/2, worker_count/0]).

-compile({inline, [member/2, partner/3, first_of/5, keep/3]}).

%% Search this far either side of the target before building everything for a full closest search
-define(NEAR_LIMIT, 8).
%% Search outwards only for full pools since smaller pools miss by more and build their subsets cheaply
-define(NEAR_FROM, 6).
%% Swap the small subsets between processes only with at least this many since one helper builds them as fast alone
-define(SWAP_FROM, 3).
%% Share the search only for pools large enough to defer two sizes since smaller pools solve in microseconds
-define(SHARE_FROM, 5).
%% Embed the subset tables for every pool of up to six numbers since they depend only on the pool size
-define(MAX_POOL, 6).

%% Lay out each round's shared counters as next task then best task then phase then waiting before the per-task slots
-define(NEXT, 1).
-define(BEST, 2).
-define(PHASE, 3).
-define(WAITING, 4).
-define(SLOTS, 4).
%% Give each task a done flag and four result slots for the left mask, both values and the operator
-define(PER_TASK, 5).
%% Mark a round over in its phase slot so late workers skip work nobody needs
-define(FINISHED, 1).
%% Cancel a round by marking its best task as before every task
-define(CANCELLED, -1).
%% Mark the best task as none with a value above any task index
-define(NO_TASK, 1000000).
%% Poll a task's done flag this many times before blocking since most tasks finish within microseconds
-define(SPINS, 200).

%% Return the simplest expression that hits the target or gets closest to it with its value
solve(Target, Pool) ->
    N = length(Pool),
    Full = (1 bsl N) - 1,
    {BySize, Splits} =
        case N =< ?MAX_POOL of
            true -> {element(N, by_size_table()), split_table()};
            false -> {masks_by_size(N, Full), list_to_tuple([splits(M) || M <- lists:seq(1, Full)])}
        end,
    St = {base_reach(Pool, Full), Splits},
    {Value, Mask, Way, St1} =
        case index_of(Target, Pool, 0) of
            none -> grow_shared(St, BySize, N, Target, Full, Pool);
            I -> {Target, 1 bsl I, none, St}
        end,
    {Value, lists:flatten(render(St1, Mask, Value, Way, true))}.

index_of(_, [], _) -> none;
index_of(T, [T | _], I) -> I;
index_of(T, [_ | Ps], I) -> index_of(T, Ps, I + 1).

%% Hold each subset's values as an ascending list for scanning and a tuple for binary search with its size
base_reach(Pool, Full) ->
    lists:foldl(fun({I, P}, R) -> setelement(1 bsl I, R, {[P], {P}, 1}) end,
                erlang:make_tuple(Full, none), lists:enumerate(0, Pool)).

%% List every subset mask of each size in ascending order for pools too large for the embedded table
masks_by_size(N, Full) ->
    list_to_tuple([[M || M <- lists:seq(1, Full), popcount(M) =:= K] || K <- lists:seq(1, N)]).

popcount(0) -> 0;
popcount(M) -> (M band 1) + popcount(M bsr 1).

%% List a subset's splits as left and right halves in the order the reference visits them
splits(Mask) -> splits(Mask, (Mask - 1) band Mask).

splits(_, 0) -> [];
splits(Mask, Left) ->
    Right = Mask bxor Left,
    Next = splits(Mask, (Left - 1) band Mask),
    case Left < Right of
        true -> [{Left, Right} | Next];
        false -> Next
    end.

%% Share the search with the workers for pools large enough to repay it and search alone otherwise
grow_shared(St, BySize, N, Target, Full, Pool) ->
    %% Share only pools whose values fit the 64-bit shared counters since a way holds two values
    Fits = lists:foldl(fun(P, Acc) -> (P + 1) * Acc end, 1, Pool) < 1 bsl 62,
    case N >= ?SHARE_FROM andalso N =< ?MAX_POOL andalso Fits andalso pool() of
        [_ | _] = Pids ->
            %% Keep this process on the first scheduler while sharing since every other scheduler holds a worker
            Bound = erlang:process_flag(scheduler, 1),
            Found = grow(St, BySize, 2, N, Target, Full, start_round(Pids, Target, Pool)),
            erlang:process_flag(scheduler, Bound),
            Found;
        _ ->
            grow(St, BySize, 2, N, Target, Full, none)
    end.

%% Search each size for the target and build its subsets only when none of them hits it
grow(St, BySize, Size, N, Target, Full, W) when Size =< N ->
    Masks = element(Size, BySize),
    case W =/= none andalso Size =:= N - 2 of
        %% Hand the deferred sizes to the shared search once every size below them is built
        true ->
            shared(St, BySize, N, Target, Full, W);
        false ->
            case first_hit(St, Masks, Target) of
                none when Size =:= N ->
                    missed(St, BySize, N, Target, Full);
                %% Share the build of the last size below the shared search with the workers
                none when W =/= none, Size =:= N - 3 ->
                    {_, Id, A, Peers} = W,
                    St1 = case length(Peers) < ?SWAP_FROM of
                              true -> build(St, Masks);
                              false -> shared_build(St, Id, A, list_to_tuple(Masks), Peers, Size, N)
                          end,
                    grow(St1, BySize, Size + 1, N, Target, Full, W);
                none ->
                    St1 = case lists:member(Size, deferred(N)) of
                              true -> St;
                              false -> build(St, Masks)
                          end,
                    grow(St1, BySize, Size + 1, N, Target, Full, W);
                Mask ->
                    W =/= none andalso finish(W),
                    {Target, Mask, none, St}
            end
    end;
grow(St, BySize, _, N, Target, Full, _) ->
    closest(St, BySize, N, Target, Full).

%% Return the first subset in mask order that can make a value
first_hit(_, [], _) -> none;
first_hit(St, [M | Ms], V) ->
    case way(St, M, V) of
        none -> first_hit(St, Ms, V);
        _ -> M
    end.

%% Build what the closest search needs once no subset of any size hits the target
missed({Reach, _} = St, BySize, N, Target, Full) ->
    St1 = lists:foldl(fun(K, S) -> build_unbuilt(S, Reach, element(K, BySize)) end, St, deferred(N) -- [N - 1]),
    case N >= ?NEAR_FROM andalso near(St1, BySize, N, Target, 1) of
        {V, Mask, St2} -> {V, Mask, none, St2};
        _ -> closest(build_all(St1, BySize, N), BySize, N, Target, Full)
    end.

%% Build a size unless an earlier step already built it
build_unbuilt(St, Reach, [First | _] = Masks) ->
    case element(First, Reach) of
        none -> build(St, Masks);
        _ -> St
    end.

%% Build any size still deferred since the full closest search needs every value of every subset
build_all(St, BySize, N) ->
    lists:foldl(fun(K, {Reach, _} = S) -> build_unbuilt(S, Reach, element(K, BySize)) end, St, deferred(N)).

%% Return the subset sizes left unbuilt until a search needs them since larger subsets can search them by nesting
deferred(N) when N >= 5 -> [N - 2, N - 1];
deferred(N) when N >= 3 -> [N - 1];
deferred(_) -> [].

%% Search every deferred size together with the workers and keep the earliest task that hits the target
shared(St, BySize, N, Target, Full, {Pids, Id, A, Peers} = W) ->
    Tasks = task_table(N),
    Total = tuple_size(Tasks),
    run_tasks(A, Id, Tasks, Total, St, Target, self()),
    Best = settle(A, Id, Total),
    atomics:put(A, ?BEST, ?CANCELLED),
    case Best < Total of
        true ->
            finish(W),
            {Mask, _, _} = element(Best + 1, Tasks),
            Base = ?SLOTS + Total + Best * 4,
            Way = {atomics:get(A, Base + 1), atomics:get(A, Base + 2), atomics:get(A, Base + 3), atomics:get(A, Base + 4)},
            {Target, Mask, Way, St};
        false ->
            %% Build the next size with the workers since the closest search needs all of its values
            [P ! {phase, Id, build_more} || P <- Pids],
            St1 = shared_build(St, Id, A, list_to_tuple(element(N - 2, BySize)), Peers, N - 2, N),
            missed(St1, BySize, N, Target, Full)
    end.

%% Tell the workers a round this process has answered is over so they drop it
finish({Pids, Id, A, _}) ->
    atomics:put(A, ?BEST, ?CANCELLED),
    atomics:put(A, ?PHASE, ?FINISHED),
    [P ! {phase, Id, finished} || P <- Pids],
    true.

%% Wait until every task before the best has finished since only then can no earlier task still hit
settle(A, Id, Total) -> wait_done(A, Id, Total, 0, ?SPINS).

%% Reread the best on every poll since a task at or past a newly lowered best may be skipped and never marked done
wait_done(A, Id, Total, I, Spins) ->
    case min(atomics:get(A, ?BEST), Total) of
        Best when I >= Best ->
            Best;
        _ ->
            case atomics:get(A, ?SLOTS + I + 1) of
                1 -> wait_done(A, Id, Total, I + 1, ?SPINS);
                _ when Spins > 0 -> wait_done(A, Id, Total, I, Spins - 1);
                _ ->
                    %% Block rather than spin since a spinning waiter starves the worker it waits for of processor time
                    atomics:put(A, ?WAITING, 1),
                    case atomics:get(A, ?SLOTS + I + 1) =:= 1 orelse I >= atomics:get(A, ?BEST) of
                        true -> ok;
                        false -> receive {done, Id} -> ok end
                    end,
                    atomics:put(A, ?WAITING, 0),
                    wait_done(A, Id, Total, I, 0)
            end
    end.

%% Claim tasks in order and run each one until none is left or the best already beats it
run_tasks(A, Id, Tasks, Total, {Reach, _} = St, Target, Caller) ->
    I = atomics:add_get(A, ?NEXT, 1) - 1,
    case I < Total andalso I < atomics:get(A, ?BEST) of
        true ->
            Found = case element(I + 1, Tasks) of
                        {Mask, 0, 0} -> way(St, Mask, Target);
                        {_, L, R} -> split_way(Reach, St, L, R, Target)
                    end,
            case Found of
                none ->
                    ok;
                {WL, X, Y, Op} ->
                    Base = ?SLOTS + Total + I * 4,
                    atomics:put(A, Base + 1, WL),
                    atomics:put(A, Base + 2, X),
                    atomics:put(A, Base + 3, Y),
                    atomics:put(A, Base + 4, Op),
                    lower_best(A, I)
            end,
            atomics:put(A, ?SLOTS + I + 1, 1),
            %% Wake the caller only when it has given up polling so most tasks cost no message
            atomics:get(A, ?WAITING) =:= 1 andalso Caller =/= self() andalso (Caller ! {done, Id}),
            run_tasks(A, Id, Tasks, Total, St, Target, Caller);
        false ->
            ok
    end.

%% Lower the shared best task to this one unless an earlier task already holds it
lower_best(A, I) ->
    Best = atomics:get(A, ?BEST),
    case I < Best andalso atomics:compare_exchange(A, ?BEST, Best, I) =/= ok of
        true -> lower_best(A, I);
        false -> ok
    end.

%% Build the claimed subsets of one size then swap them with every other process until all of them are held
shared_build({Reach, Splits}, Id, A, Masks, Peers, Size, N) ->
    Counter = ?SLOTS + tuple_size(task_table(N)) * ?PER_TASK + Size,
    Mine = claim_builds(A, Counter, Masks, Reach, Splits, []),
    case Mine of
        [] ->
            ok;
        _ ->
            %% Send one encoded binary since the virtual machine shares large binaries rather than copying them
            Bin = term_to_binary(Mine),
            Me = self(),
            [P ! {built, Id, Size, Bin} || P <- Peers, P =/= Me]
    end,
    {collect(merge(Reach, Mine), Id, Size, tuple_size(Masks) - length(Mine)), Splits}.

%% Claim subsets in turn and build each one until none is left
claim_builds(A, Counter, Masks, Reach, Splits, Built) ->
    J = atomics:add_get(A, Counter, 1),
    case J =< tuple_size(Masks) of
        true ->
            Mask = element(J, Masks),
            claim_builds(A, Counter, Masks, Reach, Splits, [{Mask, values_of(Reach, Splits, Mask)} | Built]);
        false ->
            Built
    end.

%% Receive the subsets of one size the other processes built until none is missing
collect(Reach, _, _, 0) -> Reach;
collect(Reach, Id, Size, Missing) ->
    receive
        {built, Id, Size, Bin} ->
            Parts = binary_to_term(Bin),
            collect(merge(Reach, Parts), Id, Size, Missing - length(Parts))
    end.

merge(Reach, Parts) ->
    lists:foldl(fun({Mask, Values}, R) -> setelement(Mask, R, {Values, list_to_tuple(Values), length(Values)}) end,
                Reach, Parts).

%% Return this process's pool of workers starting it on first use with one per extra scheduler
pool() ->
    case get(countdown_pool) of
        undefined ->
            Owner = self(),
            %% Bind each worker to its own scheduler so workers never queue behind one another
            Pids = [spawn_opt(fun() -> worker(monitor(process, Owner), 0) end, [{scheduler, S}])
                    || S <- lists:seq(2, worker_count())],
            put(countdown_pool, Pids),
            Pids;
        Pids ->
            Pids
    end.

%% Return how many processes share a round counting the caller and capped at the schedulers online
worker_count() ->
    Wanted = case os:getenv("COUNTDOWN_THREADS") of
                 false -> 8;
                 Text -> list_to_integer(Text)
             end,
    max(1, min(Wanted, erlang:system_info(schedulers_online))).

%% Give the workers a fresh set of shared counters and start them on the round
start_round(Pids, Target, Pool) ->
    drain(),
    N = length(Pool),
    Total = tuple_size(task_table(N)),
    A = atomics:new(?SLOTS + Total * ?PER_TASK + ?MAX_POOL, []),
    atomics:put(A, ?BEST, ?NO_TASK),
    %% Number rounds in increasing order so workers can tell stale subsets from early ones for the next round
    Id = erlang:unique_integer([monotonic]),
    Peers = [self() | Pids],
    [P ! {round, Id, A, Target, Pool, Peers} || P <- Pids],
    {Pids, Id, A, Peers}.

%% Drop messages left from rounds this process answered before every worker had finished with them
drain() ->
    receive
        {built, _, _, _} -> drain();
        {done, _} -> drain()
    after 0 -> ok
    end.

%% Wait for a round then search it alongside the caller dropping subsets sent for rounds already over
worker(Owner, Last) ->
    receive
        {round, Id, A, Target, Pool, Peers} ->
            work(Id, A, Target, Pool, Peers),
            worker(Owner, Id);
        {built, Id, _, _} when Id =< Last ->
            worker(Owner, Last);
        {'DOWN', Owner, process, _, _} ->
            ok
    end.

%% Rebuild the sizes below the shared search then claim tasks and help build the next size if asked
work(Id, A, Target, Pool, [Caller | _] = Peers) ->
    N = length(Pool),
    Ready = case atomics:get(A, ?PHASE) of
                ?FINISHED ->
                    none;
                _ ->
                    BySize = element(N, by_size_table()),
                    St0 = {base_reach(Pool, (1 bsl N) - 1), split_table()},
                    %% Rebuild the small sizes here since they take less time than receiving them
                    St1 = lists:foldl(fun(K, S) -> build(S, element(K, BySize)) end, St0, lists:seq(2, N - 4)),
                    Masks = element(N - 3, BySize),
                    St = case length(Peers) < ?SWAP_FROM of
                             true -> build(St1, Masks);
                             false -> shared_build(St1, Id, A, list_to_tuple(Masks), Peers, N - 3, N)
                         end,
                    Tasks = task_table(N),
                    run_tasks(A, Id, Tasks, tuple_size(Tasks), St, Target, Caller),
                    St
            end,
    %% Block until the caller says whether the round is over since spinning here would starve busy processes
    receive
        {phase, Id, finished} ->
            ok;
        {phase, Id, build_more} ->
            shared_build(Ready, Id, A, list_to_tuple(element(N - 2, element(N, by_size_table()))), Peers, N - 2, N)
    end.

%% Search outwards from the target one distance at a time ranking by size then mask then value
near(_, _, _, _, D) when D > ?NEAR_LIMIT -> none;
near(St, BySize, N, Target, D) ->
    Values = case Target - D >= 1 of
                 true -> [Target - D, Target + D];
                 false -> [Target + D]
             end,
    case near_sizes(St, BySize, 1, N, Values) of
        none -> near(St, BySize, N, Target, D + 1);
        {V, Mask} -> {V, Mask, St}
    end.

near_sizes(_, _, K, N, _) when K > N -> none;
near_sizes(St, BySize, K, N, Values) ->
    case near_masks(St, element(K, BySize), Values) of
        none -> near_sizes(St, BySize, K + 1, N, Values);
        Hit -> Hit
    end.

near_masks(_, [], _) -> none;
near_masks(St, [M | Ms], Values) ->
    case near_values(St, M, Values) of
        none -> near_masks(St, Ms, Values);
        V -> {V, M}
    end.

near_values(_, _, []) -> none;
near_values(St, M, [V | Vs]) ->
    case holds(St, M, V) of
        true -> V;
        false -> near_values(St, M, Vs)
    end.

%% Return whether a subset can make a value looking it up when built and searching when not
holds({Reach, _} = St, Mask, V) ->
    case element(Mask, Reach) of
        none -> way(St, Mask, V) =/= none;
        Set -> member(Set, V)
    end.

%% Store the sorted distinct values of every subset of one size
build({Reach, Splits}, Masks) ->
    {lists:foldl(fun(Mask, R) ->
                         Values = values_of(R, Splits, Mask),
                         setelement(Mask, R, {Values, list_to_tuple(Values), length(Values)})
                 end, Reach, Masks), Splits}.

%% Return the sorted distinct values one subset makes from the built subsets below it
values_of(Reach, Splits, Mask) ->
    lists:usort(lists:foldl(fun({L, R}, Made) ->
                                    {Ls, _, _} = element(L, Reach),
                                    {Rs, _, _} = element(R, Reach),
                                    pairs(Ls, Rs, Made)
                            end, [], element(Mask, Splits))).

%% Prepend every legal result of each left value with each right value
pairs([], _, Made) -> Made;
pairs([A | As], Rs, Made) -> pairs(As, Rs, pair_row(A, Rs, Made)).

%% Combine one left value with the ascending right values knowing which operand is larger
pair_row(_, [], Made) -> Made;
pair_row(A, [B | Bs], Made) when B =< A -> pair_row(A, Bs, ops(A, B, Made));
pair_row(A, Bs, Made) -> pair_row_above(A, Bs, Made).

%% Combine one left value with right values that all exceed it
pair_row_above(_, [], Made) -> Made;
pair_row_above(A, [B | Bs], Made) -> pair_row_above(A, Bs, ops(B, A, Made)).

%% Prepend every legal result of a larger value x and a smaller value y under Countdown rules
ops(X, 1, Made) when X > 1 -> [X + 1, X - 1 | Made];
ops(X, 1, Made) -> [X + 1 | Made];
ops(X, X, Made) -> [X + X, X * X, 1 | Made];
ops(X, Y, Made) when X rem Y =:= 0 -> [X + Y, X - Y, X * Y, X div Y | Made];
ops(X, Y, Made) -> [X + Y, X - Y, X * Y | Made].

%% Return whether a value is in a subset by binary search over its sorted tuple
member({_, T, Size}, V) when V < element(1, T); V > element(Size, T) -> false;
member({_, T, Size}, V) -> bsearch(T, V, 1, Size).

bsearch(_, _, Lo, Hi) when Lo > Hi -> false;
bsearch(T, V, Lo, Hi) ->
    Mid = (Lo + Hi) bsr 1,
    case element(Mid, T) of
        W when W < V -> bsearch(T, V, Mid + 1, Hi);
        W when W > V -> bsearch(T, V, Lo, Mid - 1);
        _ -> true
    end.

%% Return the first way a subset makes a value as left mask, left value, right value and operator rank
way({Reach, Splits} = St, Mask, V) -> way_from(element(Mask, Splits), Reach, St, V).

%% Try each split in turn and return the first way any of them makes the value
way_from([], _, _, _) -> none;
way_from([{L, R} | Rest], Reach, St, V) ->
    case split_way(Reach, St, L, R, V) of
        none -> way_from(Rest, Reach, St, V);
        Way -> Way
    end.

%% Return the first way one split makes a value searching an unbuilt half by nesting
split_way(Reach, St, L, R, V) ->
    case {element(L, Reach), element(R, Reach)} of
        {none, {Rs, _, _}} ->
            case nested_right(Rs, V, St, L, none) of
                none -> none;
                {A, B, Op} -> {L, A, B, Op}
            end;
        {{Ls, _, _}, none} ->
            nested_left(Ls, V, St, R, L);
        {LSet, RSet} ->
            way_split(LSet, RSet, L, V)
    end.

%% Return the first way a split makes a value scanning the shorter half and looking up partners in the other
way_split({Ls, _, LN} = LSet, {Rs, _, RN} = RSet, L, V) ->
    case LN =< RN of
        true ->
            scan_left(Ls, V, RSet, L);
        false ->
            case scan_right(Rs, V, LSet, none) of
                none -> none;
                {A, B, Op} -> {L, A, B, Op}
            end
    end.

%% Return the first left value whose partner an unbuilt right subset can make with its least such partner
nested_left([], _, _, _, _) -> none;
nested_left([A | As], V, St, R, L) ->
    case first_way(lists:sort(candidates(A, V)), St, R) of
        none -> nested_left(As, V, St, R, L);
        {B, Op} -> {L, A, B, Op}
    end.

%% Return the first candidate an unbuilt subset can make
first_way([], _, _) -> none;
first_way([{B, _} = C | Cs], St, R) ->
    case way(St, R, B) of
        none -> first_way(Cs, St, R);
        _ -> C
    end.

%% Return the least left value right value and operator where an unbuilt left subset makes the left value
nested_right([], _, _, _, Best) -> Best;
nested_right([B | Bs], V, St, L, Best) ->
    Next = case first_beating(lists:sort(candidates(B, V)), B, Best, St, L) of
               none -> Best;
               {A, Op} -> {A, B, Op}
           end,
    nested_right(Bs, V, St, L, Next).

%% Return the first candidate that beats the best so far and that an unbuilt subset can make
first_beating([], _, _, _, _) -> none;
first_beating([{A, Op} = C | Cs], B, Best, St, L) ->
    case (Best =:= none orelse {A, B, Op} < Best) andalso way(St, L, A) =/= none of
        true -> C;
        false -> first_beating(Cs, B, Best, St, L)
    end.

%% Return every number that could combine with n to make v under Countdown rules with its operator rank
candidates(N, V) ->
    F0 = case N < V of true -> [{V - N, 0}]; false -> [] end,
    F1 = case N > V of true -> [{N - V, 1} | F0]; false -> F0 end,
    F2 = [{N + V, 1} | F1],
    F3 = case V rem N =:= 0 andalso N =/= 1 andalso V =/= N of true -> [{V div N, 2} | F2]; false -> F2 end,
    F4 = case N rem V =:= 0 andalso N =/= V of true -> [{N div V, 3} | F3]; false -> F3 end,
    case N =/= 1 of true -> [{N * V, 3} | F4]; false -> F4 end.

%% Return the first left value with a partner on the right together with its least partner
scan_left([], _, _, _) -> none;
scan_left([A | As], V, RSet, L) ->
    case best_partner(A, V, RSet) of
        none -> scan_left(As, V, RSet, L);
        {B, Op} -> {L, A, B, Op}
    end.

%% Return the least left value right value and operator over every right value with a partner on the left
scan_right([], _, _, Best) -> Best;
scan_right([B | Bs], V, LSet, Best) ->
    Next = case best_partner(B, V, LSet) of
               none -> Best;
               {A, Op} when Best =:= none -> {A, B, Op};
               {A, Op} when {A, B, Op} < Best -> {A, B, Op};
               _ -> Best
           end,
    scan_right(Bs, V, LSet, Next).

%% Return the least partner of n in a set with its operator rank by checking candidates in ascending order
best_partner(N, V, Set) when N < V ->
    Low = case V rem N =:= 0 andalso N =/= 1 of
              true ->
                  Q = V div N,
                  D = V - N,
                  case Q < D of
                      true -> first_of(Q, 2, D, 0, Set);
                      false -> first_of(D, 0, Q, 2, Set)
                  end;
              false ->
                  partner(V - N, 0, Set)
          end,
    case Low of
        none ->
            case partner(N + V, 1, Set) of
                none when N =/= 1 -> partner(N * V, 3, Set);
                Hit -> Hit
            end;
        _ ->
            Low
    end;
best_partner(N, V, Set) when N > V ->
    Low = case N rem V of
              0 ->
                  Q = N div V,
                  D = N - V,
                  case Q < D of
                      true -> first_of(Q, 3, D, 1, Set);
                      false -> first_of(D, 1, Q, 3, Set)
                  end;
              _ ->
                  partner(N - V, 1, Set)
          end,
    case Low of
        %% Check the product before the sum when v is one since n times one is below n plus one
        none when V =:= 1 -> partner(N + 1, 1, Set);
        none ->
            case partner(N + V, 1, Set) of
                none -> partner(N * V, 3, Set);
                Hit -> Hit
            end;
        _ ->
            Low
    end;
best_partner(N, _, Set) ->
    case partner(N + N, 1, Set) of
        none when N =/= 1 -> partner(N * N, 3, Set);
        Hit -> Hit
    end.

%% Return the first of two candidate partners the set holds
first_of(M1, Op1, M2, Op2, Set) ->
    case partner(M1, Op1, Set) of
        none -> partner(M2, Op2, Set);
        Hit -> Hit
    end.

%% Return a candidate partner with its operator rank when the set holds it
partner(M, Op, Set) ->
    case member(Set, M) of
        true -> {M, Op};
        false -> none
    end.

%% Return the closest value as value and mask ranked by distance then numbers used then mask
closest({Reach, _} = St, BySize, N, Target, Full) ->
    Partial = lists:foldl(
                fun(Size, Best0) ->
                        lists:foldl(fun(Mask, Best) ->
                                            {_, T, Count} = element(Mask, Reach),
                                            nearest(T, Count, Target, Size, Mask, Best)
                                    end, Best0, element(Size, BySize))
                end, none, lists:seq(1, N - 1)),
    Whole = case N > 1 of
                true -> whole_best(St, Full, Target);
                false -> none
            end,
    %% Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
    case {Partial, Whole} of
        {none, none} -> {element(1, element(2, element(1, Reach))), 1, none, St};
        {none, W} -> {W, Full, none, St};
        {{_, _, _, V}, W} when W =/= none, abs(W - Target) < abs(V - Target) -> {W, Full, none, St};
        {{_, _, Mask, V}, _} -> {V, Mask, none, St}
    end.

%% Fold a subset's values either side of the target into the best key so far
nearest(T, Count, Target, Size, Mask, Best) ->
    I = lower_bound(T, Target, 1, Count + 1),
    Best1 = case I =< Count of
                true -> better(element(I, T), Target, Size, Mask, Best);
                false -> Best
            end,
    case I > 1 of
        true -> better(element(I - 1, T), Target, Size, Mask, Best1);
        false -> Best1
    end.

better(V, Target, Size, Mask, Best) ->
    Key = {abs(V - Target), Size, Mask, V},
    case Best =:= none orelse Key < Best of
        true -> Key;
        false -> Best
    end.

%% Return the position of the first value not below v in a sorted tuple
lower_bound(_, _, Lo, Hi) when Lo >= Hi -> Lo;
lower_bound(T, V, Lo, Hi) ->
    Mid = (Lo + Hi) bsr 1,
    case element(Mid, T) < V of
        true -> lower_bound(T, V, Mid + 1, Hi);
        false -> lower_bound(T, V, Lo, Mid)
    end.

%% Return the whole pool's value closest to the target preferring the lower value on equal distance
whole_best({Reach, Splits}, Full, Target) ->
    {_, V} = lists:foldl(fun({L, R}, Acc) ->
                                 {Ls, _, _} = element(L, Reach),
                                 {Rs, _, _} = element(R, Reach),
                                 whole_rows(Ls, Rs, Target, Acc)
                         end, {none, none}, element(Full, Splits)),
    V.

whole_rows([], _, _, Acc) -> Acc;
whole_rows([A | As], Rs, T, Acc) -> whole_rows(As, Rs, T, whole_row(A, Rs, T, Acc)).

whole_row(_, [], _, Acc) -> Acc;
whole_row(A, [B | Bs], T, Acc) ->
    {X, Y} = case A >= B of
                 true -> {A, B};
                 false -> {B, A}
             end,
    Acc1 = keep(X + Y, T, Acc),
    Acc2 = case X > Y of
               true -> keep(X - Y, T, Acc1);
               false -> Acc1
           end,
    Acc3 = if
               Y =:= 1 -> Acc2;
               X rem Y =:= 0 -> keep(X div Y, T, keep(X * Y, T, Acc2));
               true -> keep(X * Y, T, Acc2)
           end,
    whole_row(A, Bs, T, Acc3).

keep(V, T, {D, W} = Acc) ->
    E = abs(V - T),
    case D =:= none orelse E < D orelse (E =:= D andalso V < W) of
        true -> {E, V};
        false -> Acc
    end.

%% Write the canonical expression for a value made from a subset with brackets unless it is outermost
render(_, Mask, V, _, _) when Mask band (Mask - 1) =:= 0 ->
    integer_to_list(V);
render(St, Mask, V, Way, Outer) ->
    %% Reuse the way the shared search already found rather than searching for it again
    {L, A, B, Op} = case Way of
                        none -> way(St, Mask, V);
                        _ -> Way
                    end,
    R = Mask bxor L,
    {LM, X, SM, Y} = case A >= B of
                         true -> {L, A, R, B};
                         false -> {R, B, L, A}
                     end,
    Inner = [render(St, LM, X, none, false), element(Op + 1, {" + ", " - ", " * ", " / "}), render(St, SM, Y, none, false)],
    case Outer of
        true -> Inner;
        false -> [$(, Inner, $)]
    end.

%% List each subset's splits by mask as left and right halves in the order the reference visits them
split_table() ->
    {[],
     [],
     [{1,2}],
     [],
     [{1,4}],
     [{2,4}],
     [{3,4},{2,5},{1,6}],
     [],
     [{1,8}],
     [{2,8}],
     [{3,8},{2,9},{1,10}],
     [{4,8}],
     [{5,8},{4,9},{1,12}],
     [{6,8},{4,10},{2,12}],
     [{7,8},{6,9},{5,10},{4,11},{3,12},{2,13},{1,14}],
     [],
     [{1,16}],
     [{2,16}],
     [{3,16},{2,17},{1,18}],
     [{4,16}],
     [{5,16},{4,17},{1,20}],
     [{6,16},{4,18},{2,20}],
     [{7,16},{6,17},{5,18},{4,19},{3,20},{2,21},{1,22}],
     [{8,16}],
     [{9,16},{8,17},{1,24}],
     [{10,16},{8,18},{2,24}],
     [{11,16},{10,17},{9,18},{8,19},{3,24},{2,25},{1,26}],
     [{12,16},{8,20},{4,24}],
     [{13,16},{12,17},{9,20},{8,21},{5,24},{4,25},{1,28}],
     [{14,16},{12,18},{10,20},{8,22},{6,24},{4,26},{2,28}],
     [{15,16},{14,17},{13,18},{12,19},{11,20},{10,21},{9,22},{8,23},{7,24},{6,25},{5,26},{4,27},{3,28},{2,29},{1,30}],
     [],
     [{1,32}],
     [{2,32}],
     [{3,32},{2,33},{1,34}],
     [{4,32}],
     [{5,32},{4,33},{1,36}],
     [{6,32},{4,34},{2,36}],
     [{7,32},{6,33},{5,34},{4,35},{3,36},{2,37},{1,38}],
     [{8,32}],
     [{9,32},{8,33},{1,40}],
     [{10,32},{8,34},{2,40}],
     [{11,32},{10,33},{9,34},{8,35},{3,40},{2,41},{1,42}],
     [{12,32},{8,36},{4,40}],
     [{13,32},{12,33},{9,36},{8,37},{5,40},{4,41},{1,44}],
     [{14,32},{12,34},{10,36},{8,38},{6,40},{4,42},{2,44}],
     [{15,32},{14,33},{13,34},{12,35},{11,36},{10,37},{9,38},{8,39},{7,40},{6,41},{5,42},{4,43},{3,44},{2,45},{1,46}],
     [{16,32}],
     [{17,32},{16,33},{1,48}],
     [{18,32},{16,34},{2,48}],
     [{19,32},{18,33},{17,34},{16,35},{3,48},{2,49},{1,50}],
     [{20,32},{16,36},{4,48}],
     [{21,32},{20,33},{17,36},{16,37},{5,48},{4,49},{1,52}],
     [{22,32},{20,34},{18,36},{16,38},{6,48},{4,50},{2,52}],
     [{23,32},{22,33},{21,34},{20,35},{19,36},{18,37},{17,38},{16,39},{7,48},{6,49},{5,50},{4,51},{3,52},{2,53},{1,54}],
     [{24,32},{16,40},{8,48}],
     [{25,32},{24,33},{17,40},{16,41},{9,48},{8,49},{1,56}],
     [{26,32},{24,34},{18,40},{16,42},{10,48},{8,50},{2,56}],
     [{27,32},{26,33},{25,34},{24,35},{19,40},{18,41},{17,42},{16,43},{11,48},{10,49},{9,50},{8,51},{3,56},{2,57},{1,58}],
     [{28,32},{24,36},{20,40},{16,44},{12,48},{8,52},{4,56}],
     [{29,32},{28,33},{25,36},{24,37},{21,40},{20,41},{17,44},{16,45},{13,48},{12,49},{9,52},{8,53},{5,56},{4,57},{1,60}],
     [{30,32},{28,34},{26,36},{24,38},{22,40},{20,42},{18,44},{16,46},{14,48},{12,50},{10,52},{8,54},{6,56},{4,58},{2,60}],
     [{31,32},{30,33},{29,34},{28,35},{27,36},{26,37},{25,38},{24,39},{23,40},{22,41},{21,42},{20,43},{19,44},{18,45},{17,46},{16,47},{15,48},{14,49},{13,50},{12,51},{11,52},{10,53},{9,54},{8,55},{7,56},{6,57},{5,58},{4,59},{3,60},{2,61},{1,62}]}.

%% List every subset mask of each size in ascending order for each pool size up to six
by_size_table() ->
    {{[1]},
     {[1,2],[3]},
     {[1,2,4],[3,5,6],[7]},
     {[1,2,4,8],[3,5,6,9,10,12],[7,11,13,14],[15]},
     {[1,2,4,8,16],[3,5,6,9,10,12,17,18,20,24],[7,11,13,14,19,21,22,25,26,28],[15,23,27,29,30],[31]},
     {[1,2,4,8,16,32],[3,5,6,9,10,12,17,18,20,24,33,34,36,40,48],[7,11,13,14,19,21,22,25,26,28,35,37,38,41,42,44,49,50,52,56],[15,23,27,29,30,39,43,45,46,51,53,54,57,58,60],[31,47,55,59,61,62],[63]}}.

%% List the shared search tasks in the order the sequential search would try them with whole masks for the cheapest size
task_table(5) ->
    {{7,0,0},
     {11,0,0},
     {13,0,0},
     {14,0,0},
     {19,0,0},
     {21,0,0},
     {22,0,0},
     {25,0,0},
     {26,0,0},
     {28,0,0},
     {15,7,8},
     {15,6,9},
     {15,5,10},
     {15,4,11},
     {15,3,12},
     {15,2,13},
     {15,1,14},
     {23,7,16},
     {23,6,17},
     {23,5,18},
     {23,4,19},
     {23,3,20},
     {23,2,21},
     {23,1,22},
     {27,11,16},
     {27,10,17},
     {27,9,18},
     {27,8,19},
     {27,3,24},
     {27,2,25},
     {27,1,26},
     {29,13,16},
     {29,12,17},
     {29,9,20},
     {29,8,21},
     {29,5,24},
     {29,4,25},
     {29,1,28},
     {30,14,16},
     {30,12,18},
     {30,10,20},
     {30,8,22},
     {30,6,24},
     {30,4,26},
     {30,2,28},
     {31,15,16},
     {31,14,17},
     {31,13,18},
     {31,12,19},
     {31,11,20},
     {31,10,21},
     {31,9,22},
     {31,8,23},
     {31,7,24},
     {31,6,25},
     {31,5,26},
     {31,4,27},
     {31,3,28},
     {31,2,29},
     {31,1,30}};
task_table(6) ->
    {{15,0,0},
     {23,0,0},
     {27,0,0},
     {29,0,0},
     {30,0,0},
     {39,0,0},
     {43,0,0},
     {45,0,0},
     {46,0,0},
     {51,0,0},
     {53,0,0},
     {54,0,0},
     {57,0,0},
     {58,0,0},
     {60,0,0},
     {31,15,16},
     {31,14,17},
     {31,13,18},
     {31,12,19},
     {31,11,20},
     {31,10,21},
     {31,9,22},
     {31,8,23},
     {31,7,24},
     {31,6,25},
     {31,5,26},
     {31,4,27},
     {31,3,28},
     {31,2,29},
     {31,1,30},
     {47,15,32},
     {47,14,33},
     {47,13,34},
     {47,12,35},
     {47,11,36},
     {47,10,37},
     {47,9,38},
     {47,8,39},
     {47,7,40},
     {47,6,41},
     {47,5,42},
     {47,4,43},
     {47,3,44},
     {47,2,45},
     {47,1,46},
     {55,23,32},
     {55,22,33},
     {55,21,34},
     {55,20,35},
     {55,19,36},
     {55,18,37},
     {55,17,38},
     {55,16,39},
     {55,7,48},
     {55,6,49},
     {55,5,50},
     {55,4,51},
     {55,3,52},
     {55,2,53},
     {55,1,54},
     {59,27,32},
     {59,26,33},
     {59,25,34},
     {59,24,35},
     {59,19,40},
     {59,18,41},
     {59,17,42},
     {59,16,43},
     {59,11,48},
     {59,10,49},
     {59,9,50},
     {59,8,51},
     {59,3,56},
     {59,2,57},
     {59,1,58},
     {61,29,32},
     {61,28,33},
     {61,25,36},
     {61,24,37},
     {61,21,40},
     {61,20,41},
     {61,17,44},
     {61,16,45},
     {61,13,48},
     {61,12,49},
     {61,9,52},
     {61,8,53},
     {61,5,56},
     {61,4,57},
     {61,1,60},
     {62,30,32},
     {62,28,34},
     {62,26,36},
     {62,24,38},
     {62,22,40},
     {62,20,42},
     {62,18,44},
     {62,16,46},
     {62,14,48},
     {62,12,50},
     {62,10,52},
     {62,8,54},
     {62,6,56},
     {62,4,58},
     {62,2,60},
     {63,31,32},
     {63,30,33},
     {63,29,34},
     {63,28,35},
     {63,27,36},
     {63,26,37},
     {63,25,38},
     {63,24,39},
     {63,23,40},
     {63,22,41},
     {63,21,42},
     {63,20,43},
     {63,19,44},
     {63,18,45},
     {63,17,46},
     {63,16,47},
     {63,15,48},
     {63,14,49},
     {63,13,50},
     {63,12,51},
     {63,11,52},
     {63,10,53},
     {63,9,54},
     {63,8,55},
     {63,7,56},
     {63,6,57},
     {63,5,58},
     {63,4,59},
     {63,3,60},
     {63,2,61},
     {63,1,62}}.
