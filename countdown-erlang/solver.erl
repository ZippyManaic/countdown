%% Work out the simplest Countdown expression that hits a target or gets closest to it
-module(solver).
-export([solve/2]).

-compile({inline, [member/2, partner/3, first_of/5, keep/3]}).

%% Search this far either side of the target before building everything for a full closest search
-define(NEAR_LIMIT, 8).
%% Search outwards only for full pools since smaller pools miss by more and build their subsets cheaply
-define(NEAR_FROM, 6).
%% Embed the subset tables for every pool of up to six numbers since they depend only on the pool size
-define(MAX_POOL, 6).

%% Return the simplest expression that hits the target or gets closest to it with its value
solve(Target, Pool) ->
    N = length(Pool),
    Full = (1 bsl N) - 1,
    {BySize, Splits} =
        case N =< ?MAX_POOL of
            true -> {element(N, by_size_table()), split_table()};
            false -> {masks_by_size(N, Full), list_to_tuple([splits(M) || M <- lists:seq(1, Full)])}
        end,
    %% Hold each subset's values as an ascending list for scanning and a tuple for binary search with its size
    Reach = lists:foldl(fun({I, P}, R) -> setelement(1 bsl I, R, {[P], {P}, 1}) end,
                        erlang:make_tuple(Full, none), lists:enumerate(0, Pool)),
    St = {Reach, Splits},
    {Value, Mask, St1} =
        case index_of(Target, Pool, 0) of
            none -> grow(St, BySize, 2, N, Target, Full);
            I -> {Target, 1 bsl I, St}
        end,
    {Value, lists:flatten(render(St1, Mask, Value, true))}.

index_of(_, [], _) -> none;
index_of(T, [T | _], I) -> I;
index_of(T, [_ | Ps], I) -> index_of(T, Ps, I + 1).

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

%% Search each size for the target and build its subsets only when none of them hits it
grow(St, BySize, Size, N, Target, Full) when Size =< N ->
    Masks = element(Size, BySize),
    case first_hit(St, Masks, Target) of
        %% Build every deferred size but the largest so searches for nearby values can nest cheaply
        none when Size =:= N ->
            St1 = lists:foldl(fun(K, S) -> build(S, element(K, BySize)) end, St, deferred(N) -- [N - 1]),
            Near = case N >= ?NEAR_FROM of
                       true -> near(St1, BySize, N, Target, 1);
                       false -> none
                   end,
            case Near of
                none -> closest(build_all(St1, BySize, N), BySize, N, Target, Full);
                Hit -> Hit
            end;
        none ->
            St1 = case lists:member(Size, deferred(N)) of
                      true -> St;
                      false -> build(St, Masks)
                  end,
            grow(St1, BySize, Size + 1, N, Target, Full);
        Mask ->
            {Target, Mask, St}
    end;
grow(St, BySize, _, N, Target, Full) ->
    closest(St, BySize, N, Target, Full).

%% Return the first subset in mask order that can make a value
first_hit(_, [], _) -> none;
first_hit(St, [Mask | Masks], V) ->
    case way(St, Mask, V) of
        none -> first_hit(St, Masks, V);
        _ -> Mask
    end.

%% Build any size still deferred since the full closest search needs every value of every subset
build_all(St, BySize, N) ->
    lists:foldl(fun(K, {Reach, _} = S) ->
                        Masks = element(K, BySize),
                        case element(hd(Masks), Reach) of
                            none -> build(S, Masks);
                            _ -> S
                        end
                end, St, deferred(N)).

%% Search outwards from the target one distance at a time ranking by size then mask then value
near(_, _, _, _, D) when D > ?NEAR_LIMIT -> none;
near(St, BySize, N, Target, D) ->
    Values = case Target - D >= 1 of
                 true -> [Target - D, Target + D];
                 false -> [Target + D]
             end,
    case near_sizes(St, BySize, 1, N, Values) of
        none -> near(St, BySize, N, Target, D + 1);
        Hit -> Hit
    end.

near_sizes(_, _, K, N, _) when K > N -> none;
near_sizes(St, BySize, K, N, Values) ->
    case near_masks(St, element(K, BySize), Values) of
        none -> near_sizes(St, BySize, K + 1, N, Values);
        Hit -> Hit
    end.

near_masks(_, [], _) -> none;
near_masks(St, [Mask | Masks], Values) ->
    case near_values(St, Mask, Values) of
        none -> near_masks(St, Masks, Values);
        V -> {V, Mask, St}
    end.

near_values(_, _, []) -> none;
near_values(St, Mask, [V | Vs]) ->
    case holds(St, Mask, V) of
        true -> V;
        false -> near_values(St, Mask, Vs)
    end.

%% Return whether a subset can make a value looking it up when built and searching when not
holds({Reach, _} = St, Mask, V) ->
    case element(Mask, Reach) of
        none -> way(St, Mask, V) =/= none;
        Set -> member(Set, V)
    end.

%% Return the subset sizes left unbuilt until a search needs them since larger subsets can search them by nesting
deferred(N) when N >= 5 -> [N - 2, N - 1];
deferred(N) when N >= 3 -> [N - 1];
deferred(_) -> [].

%% Store the sorted distinct values of every subset of one size
build({Reach, Splits}, Masks) ->
    Reach1 = lists:foldl(
               fun(Mask, Acc) ->
                       Made = lists:foldl(
                                fun({L, R}, M) ->
                                        {Ls, _, _} = element(L, Acc),
                                        {Rs, _, _} = element(R, Acc),
                                        pairs(Ls, Rs, M)
                                end, [], element(Mask, Splits)),
                       Values = lists:usort(Made),
                       setelement(Mask, Acc, {Values, list_to_tuple(Values), length(Values)})
               end, Reach, Masks),
    {Reach1, Splits}.

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
    Found = case {element(L, Reach), element(R, Reach)} of
                %% Search an unbuilt half by nesting while scanning the built half
                {none, {Rs, _, _}} ->
                    case nested_right(Rs, V, St, L, none) of
                        none -> none;
                        {A, B, Op} -> {L, A, B, Op}
                    end;
                {{Ls, _, _}, none} ->
                    nested_left(Ls, V, St, R, L);
                {LSet, RSet} ->
                    way_split(LSet, RSet, L, V)
            end,
    case Found of
        none -> way_from(Rest, Reach, St, V);
        _ -> Found
    end.

%% Return the first way a split makes a value scanning the shorter half and looking up partners in the other
way_split({Ls, _, LN} = LSet, {Rs, _, RN} = RSet, L, V) ->
    case LN =< RN of
        true -> scan_left(Ls, V, RSet, L);
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

first_way([], _, _) -> none;
first_way([{B, _} = C | Cs], St, R) ->
    case way(St, R, B) of
        none -> first_way(Cs, St, R);
        _ -> C
    end.

%% Return the least left value right value and operator where an unbuilt left subset makes the left value
nested_right([], _, _, _, Best) -> Best;
nested_right([B | Bs], V, St, L, Best) ->
    Best1 = case first_beating(lists:sort(candidates(B, V)), B, St, L, Best) of
                none -> Best;
                {A, Op} -> {A, B, Op}
            end,
    nested_right(Bs, V, St, L, Best1).

first_beating([], _, _, _, _) -> none;
first_beating([{A, Op} = C | Cs], B, St, L, Best) ->
    case (Best =:= none orelse {A, B, Op} < Best) andalso way(St, L, A) =/= none of
        true -> C;
        false -> first_beating(Cs, B, St, L, Best)
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
    Best1 = case best_partner(B, V, LSet) of
                none -> Best;
                {A, Op} when Best =:= none; {A, B, Op} < Best -> {A, B, Op};
                _ -> Best
            end,
    scan_right(Bs, V, LSet, Best1).

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
        _ -> Low
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
        _ -> Low
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
                fun(Size, Best) ->
                        lists:foldl(fun(Mask, B) ->
                                            {_, T, Count} = element(Mask, Reach),
                                            nearest(T, Count, Target, Size, Mask, B)
                                    end, Best, element(Size, BySize))
                end, none, lists:seq(1, N - 1)),
    Whole = case N > 1 of
                true -> whole_best(St, Full, Target);
                false -> none
            end,
    %% Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
    case {Partial, Whole} of
        {none, none} -> {element(1, element(2, element(1, Reach))), 1, St};
        {none, W} -> {W, Full, St};
        {{_, _, _, V}, W} when W =/= none, abs(W - Target) < abs(V - Target) -> {W, Full, St};
        {{_, _, Mask, V}, _} -> {V, Mask, St}
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
    {X, Y} = case A >= B of true -> {A, B}; false -> {B, A} end,
    Acc1 = keep(X + Y, T, Acc),
    Acc2 = case X > Y of true -> keep(X - Y, T, Acc1); false -> Acc1 end,
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
render(St, Mask, V, Outer) ->
    case Mask band (Mask - 1) of
        0 -> integer_to_list(V);
        _ ->
            {L, A, B, Op} = way(St, Mask, V),
            R = Mask bxor L,
            {LM, X, SM, Y} = case A >= B of
                                 true -> {L, A, R, B};
                                 false -> {R, B, L, A}
                             end,
            Inner = [render(St, LM, X, false), element(Op + 1, {" + ", " - ", " * ", " / "}),
                     render(St, SM, Y, false)],
            case Outer of
                true -> Inner;
                false -> [$(, Inner, $)]
            end
    end.

%% Return each subset's splits as left and right halves in the order the reference visits them for pools of up to six numbers
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

%% Return the subset masks of each size in ascending order for each pool size up to six
by_size_table() ->
    {{[1]},
     {[1,2],[3]},
     {[1,2,4],[3,5,6],[7]},
     {[1,2,4,8],[3,5,6,9,10,12],[7,11,13,14],[15]},
     {[1,2,4,8,16],[3,5,6,9,10,12,17,18,20,24],[7,11,13,14,19,21,22,25,26,28],[15,23,27,29,30],[31]},
     {[1,2,4,8,16,32],[3,5,6,9,10,12,17,18,20,24,33,34,36,40,48],[7,11,13,14,19,21,22,25,26,28,35,37,38,41,42,44,49,50,52,56],[15,23,27,29,30,39,43,45,46,51,53,54,57,58,60],[31,47,55,59,61,62],[63]}}.
