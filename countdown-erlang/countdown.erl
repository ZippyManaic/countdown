%% Generate a Countdown numbers round and work out whether it can be solved
-module(countdown).
-export([main/0, generate_round/0]).

-define(LARGE_NUMBERS, [25, 50, 75, 100]).

%% Shuffle a list by sorting it on random keys
shuffle(Items) ->
    [X || {_, X} <- lists:sort([{rand:uniform(), X} || X <- Items])].

%% Return a random target and a pool of six numbers with either one or two large numbers
generate_round() ->
    Target = 99 + rand:uniform(900),
    LargeCount = rand:uniform(2),
    %% Hold two cards of each small number to match the game's deck
    Small = lists:sublist(shuffle(lists:seq(1, 10) ++ lists:seq(1, 10)), 6 - LargeCount),
    %% Shuffle a copy since each large number appears only once in the game
    Large = lists:sublist(shuffle(?LARGE_NUMBERS), LargeCount),
    {Target, Small ++ Large}.

main() ->
    {Target, Pool} = generate_round(),
    io:format("Target: ~w~n", [Target]),
    io:format("Pool:   ~s~n", [lists:join(" ", [integer_to_list(P) || P <- Pool])]),
    {Value, Expr} = solver:solve(Target, Pool),
    case Value of
        Target ->
            io:format("Solved: ~s = ~w~n", [Expr, Value]),
            halt(0);
        _ ->
            io:format("No exact solution, closest is ~s = ~w (~w away)~n", [Expr, Value, abs(Target - Value)]),
            halt(1)
    end.
