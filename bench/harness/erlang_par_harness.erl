%% Time the parallel Erlang solver over a file of rounds and write each answer as value tab expression
-module(erlang_par_harness).
-export([main/1]).

main([RoundsPath, OutPath | Rest]) ->
    Reps = case Rest of [R | _] -> list_to_integer(R); [] -> 1 end,
    {ok, Text} = file:read_file(RoundsPath),
    Rounds = [begin [T | P] = [binary_to_integer(W) || W <- binary:split(Line, <<" ">>, [global, trim_all])], {T, P} end
              || Line <- binary:split(Text, <<"\n">>, [global, trim_all])],
    Count = length(Rounds),
    %% Warm up with untimed passes so the timing matches the other JIT-compiled languages
    [solve_all(Rounds) || _ <- lists:seq(1, 3)],
    Start = erlang:monotonic_time(nanosecond),
    Answers = lists:last([solve_all(Rounds) || _ <- lists:seq(1, Reps)]),
    Stop = erlang:monotonic_time(nanosecond),
    io:format(standard_error, "~.4f ms/round~n", [(Stop - Start) / 1.0e6 / Count / Reps]),
    Lines = lists:join($\n, [[integer_to_list(V), $\t, E] || {V, E} <- Answers]),
    ok = file:write_file(OutPath, Lines),
    halt(0).

%% Solve every round in order
solve_all(Rounds) ->
    [solver_par:solve(T, P) || {T, P} <- Rounds].
