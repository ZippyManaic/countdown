%% Generate a Countdown numbers round and work out whether it can be solved sharing the round across processes
-module(countdown_par).
-export([main/0, generate_round/0, generate_round/1, generate_round/2, parse_args/1, large_numbers/1, allowed_counts/1]).

-define(USAGE, "usage: countdown [standard|cats|nasty] [LARGE]").

%% Return the large cards of a mode, with nasty-cats using the cards of the 2010 specials
large_numbers(nasty) -> [12, 37, 62, 87];
large_numbers(_) -> [25, 50, 75, 100].

%% Return the large counts a mode allows
allowed_counts(standard) -> [1, 2];
allowed_counts(_) -> [0, 1, 2, 3, 4].

%% Shuffle a list by sorting it on random keys
shuffle(Items) ->
    [X || {_, X} <- lists:sort([{rand:uniform(), X} || X <- Items])].

generate_round() -> generate_round(standard).

generate_round(Mode) -> generate_round(Mode, undefined).

%% Return a random target and six numbers with one or two large in standard mode and none to four otherwise
generate_round(Mode, Fixed) ->
    Target = 99 + rand:uniform(900),
    LargeCount = case Fixed of
                     undefined when Mode =:= standard -> rand:uniform(2);
                     undefined -> rand:uniform(5) - 1;
                     _ -> Fixed
                 end,
    %% Hold two cards of each small number to match the game's deck
    Small = lists:sublist(shuffle(lists:seq(1, 10) ++ lists:seq(1, 10)), 6 - LargeCount),
    %% Shuffle a copy since each large number appears only once in the game
    Large = lists:sublist(shuffle(large_numbers(Mode)), LargeCount),
    {Target, Small ++ Large}.

parse_mode("standard") -> standard;
parse_mode("cats") -> cats;
parse_mode("nasty") -> nasty;
parse_mode(_) -> error.

%% Return the mode and fixed large count from the command line, or error when the arguments are invalid
parse_args([]) -> {standard, undefined};
parse_args([M]) ->
    case parse_mode(M) of
        error -> error;
        Mode -> {Mode, undefined}
    end;
parse_args([M, N]) ->
    case parse_mode(M) of
        error -> error;
        Mode ->
            case [K || K <- allowed_counts(Mode), integer_to_list(K) =:= N] of
                [K] -> {Mode, K};
                [] -> error
            end
    end;
parse_args(_) -> error.

%% Read the arguments the launcher passes after -extra
main() ->
    case parse_args(init:get_plain_arguments()) of
        error ->
            io:format(standard_error, "~s~n", [?USAGE]),
            halt(2);
        {Mode, Fixed} ->
            play(Mode, Fixed)
    end.

play(Mode, Fixed) ->
    {Target, Pool} = generate_round(Mode, Fixed),
    io:format("Target: ~w~n", [Target]),
    io:format("Pool:   ~s~n", [lists:join(" ", [integer_to_list(P) || P <- Pool])]),
    {Value, Expr} = solver_par:solve(Target, Pool),
    case Value of
        Target ->
            io:format("Solved: ~s = ~w~n", [Expr, Value]),
            halt(0);
        _ ->
            io:format("No exact solution, closest is ~s = ~w (~w away)~n", [Expr, Value, abs(Target - Value)]),
            halt(1)
    end.
