%% Check the solver against known answers and the dealer against the game's rules
-module(solver_tests).
-include_lib("eunit/include/eunit.hrl").

finds_simplest_solution_test() ->
    ?assertEqual({125, "75 + 50"}, solver:solve(125, [1, 5, 7, 3, 75, 50])),
    ?assertMatch({552, _}, solver:solve(552, [8, 4, 2, 5, 100, 25])).

reports_closest_when_unsolvable_test() ->
    {Value, _} = solver:solve(974, [8, 8, 6, 8, 25, 100]),
    ?assertEqual(1, abs(Value - 974)).

handles_smaller_pools_test() ->
    ?assertEqual({7, "7"}, solver:solve(7, [7])),
    ?assertEqual({7, "7"}, solver:solve(10, [7])),
    ?assertEqual({12, "4 * 3"}, solver:solve(10, [3, 4])),
    ?assertEqual({6, "3 * 2"}, solver:solve(6, [2, 3, 50])).

deals_a_valid_pool_test() ->
    [begin
         {Target, Pool} = countdown:generate_round(),
         ?assert(Target >= 100 andalso Target =< 999),
         ?assertEqual(6, length(Pool)),
         Large = length([P || P <- Pool, P > 10]),
         ?assert(Large =:= 1 orelse Large =:= 2),
         [?assert(length([P || P <- Pool, P =:= N]) =< 2) || N <- lists:seq(1, 10)]
     end || _ <- lists:seq(1, 1000)].

%% Return the large count of a dealt round after checking it keeps the rules of its mode
check_round(Mode, Counts, {Target, Pool}) ->
    ?assert(Target >= 100 andalso Target =< 999),
    ?assertEqual(6, length(Pool)),
    Large = [P || P <- Pool, P > 10],
    ?assert(lists:member(length(Large), Counts)),
    ?assertEqual([], Large -- countdown:large_numbers(Mode)),
    ?assertEqual(length(Large), length(lists:usort(Large))),
    %% Allow each small number at most twice since the deck holds two of each
    [?assert(length([P || P <- Pool, P =:= N]) =< 2) || N <- lists:seq(1, 10)],
    length(Large).

deals_every_mode_test() ->
    rand:seed(exsss, 1),
    [begin
         Counts = countdown:allowed_counts(Mode),
         Seen = [check_round(Mode, Counts, countdown:generate_round(Mode)) || _ <- lists:seq(1, 2000)],
         ?assertEqual(Counts, lists:usort(Seen))
     end || Mode <- [standard, cats, nasty]].

deals_a_fixed_large_count_test() ->
    [?assertEqual(K, check_round(Mode, [K], countdown:generate_round(Mode, K))) || Mode <- [cats, nasty], K <- lists:seq(0, 4)].

parses_arguments_test() ->
    ?assertEqual({standard, undefined}, countdown:parse_args([])),
    ?assertEqual({nasty, 4}, countdown:parse_args(["nasty", "4"])),
    ?assertEqual({cats, 0}, countdown:parse_args(["cats", "0"])),
    [?assertEqual(error, countdown:parse_args(Bad)) || Bad <- [["standard", "3"], ["cats", "5"], ["dogs"], ["cats", "1", "2"], ["cats", "x"]]].

solves_cats_rounds_test() ->
    ?assertEqual({999, "(((75 + 25) * 100) - 10) / 10"}, solver:solve(999, [10, 10, 25, 50, 75, 100])),
    ?assertEqual({81, "(((2 + 1) * (2 + 1)) * 3) * 3"}, solver:solve(100, [1, 1, 2, 2, 3, 3])),
    ?assertEqual({999, "37 * ((87 / 3) - 2)"}, solver:solve(999, [2, 3, 87, 62, 37, 12])).
