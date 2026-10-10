! Check the dealer in every mode and the solver against rounds with known answers
program test_solver
    use countdown_round, only: mode_standard, mode_cats, mode_nasty, random_large, large_numbers, deal_round, parse_args
    use countdown_solver, only: solve_round
    use iso_fortran_env, only: int32
    implicit none
    integer(int32) :: value
    character(:), allocatable :: expr
    integer :: failures, mode, large_count
    logical :: ok

    failures = 0
    call solve_round(125, [1, 5, 7, 3, 75, 50], value, expr)
    call expect(value == 125 .and. expr == '75 + 50', 'finds simplest solution')
    call solve_round(552, [8, 4, 2, 5, 100, 25], value, expr)
    call expect(value == 552, 'solves 552')
    call solve_round(974, [8, 8, 6, 8, 25, 100], value, expr)
    call expect(abs(value - 974) == 1, 'reports closest when unsolvable')
    call solve_round(100, [7], value, expr)
    call expect(value == 7 .and. expr == '7', 'reports a lone number as closest')
    call solve_round(7, [7], value, expr)
    call expect(value == 7 .and. expr == '7', 'solves with a lone number')
    call solve_round(100, [3, 4], value, expr)
    call expect(value == 12 .and. expr == '4 * 3', 'reports closest with two numbers')
    call solve_round(999, [10, 10, 25, 50, 75, 100], value, expr)
    call expect(value == 999 .and. expr == '(((75 + 25) * 100) - 10) / 10', 'solves 999 with four large')
    call solve_round(100, [1, 1, 2, 2, 3, 3], value, expr)
    call expect(value == 81 .and. expr == '(((2 + 1) * (2 + 1)) * 3) * 3', 'reports closest with no large')
    call solve_round(999, [2, 3, 87, 62, 37, 12], value, expr)
    call expect(value == 999 .and. expr == '37 * ((87 / 3) - 2)', 'solves 999 with nasty large numbers')

    call random_init(repeatable=.false., image_distinct=.true.)
    call check_mode(mode_standard, 'standard', [.false., .true., .true., .false., .false.])
    call check_mode(mode_cats, 'cats', [.true., .true., .true., .true., .true.])
    call check_mode(mode_nasty, 'nasty', [.true., .true., .true., .true., .true.])

    call parse_args([character(8) ::], mode, large_count, ok)
    call expect(ok .and. mode == mode_standard .and. large_count == random_large, 'parses no arguments')
    call parse_args([character(8) :: 'nasty', '4'], mode, large_count, ok)
    call expect(ok .and. mode == mode_nasty .and. large_count == 4, 'parses nasty 4')
    call parse_args([character(8) :: 'cats', '0'], mode, large_count, ok)
    call expect(ok .and. mode == mode_cats .and. large_count == 0, 'parses cats 0')
    call parse_args([character(8) :: 'standard', '3'], mode, large_count, ok)
    call expect(.not. ok, 'rejects standard 3')
    call parse_args([character(8) :: 'cats', '5'], mode, large_count, ok)
    call expect(.not. ok, 'rejects cats 5')
    call parse_args([character(8) :: 'dogs'], mode, large_count, ok)
    call expect(.not. ok, 'rejects an unknown mode')
    call parse_args([character(8) :: 'cats', '1', '2'], mode, large_count, ok)
    call expect(.not. ok, 'rejects three arguments')
    call parse_args([character(8) :: 'cats', 'x'], mode, large_count, ok)
    call expect(.not. ok, 'rejects a non-numeric count')
    if (failures > 0) stop 1, quiet=.true.
    print '(a)', 'all tests passed'

contains

    ! Deal many rounds in a mode and check each one and that exactly the allowed large counts occur
    subroutine check_mode(mode, name, allowed)
        integer, intent(in) :: mode
        character(*), intent(in) :: name
        logical, intent(in) :: allowed(0:4)
        integer(int32) :: target, pool(6)
        logical :: seen(0:4), valid
        integer :: r, k, count

        seen = .false.
        valid = .true.
        do r = 1, 2000
            call deal_round(mode, random_large, target, pool)
            count = check_round(mode, target, pool)
            if (count < 0) then
                valid = .false.
            else
                seen(count) = .true.
            end if
        end do
        call expect(valid .and. all(seen .eqv. allowed), name)
        if (mode == mode_standard) return
        do k = 0, 4
            call deal_round(mode, k, target, pool)
            call expect(check_round(mode, target, pool) == k, 'deals the fixed large count')
        end do
    end subroutine check_mode

    ! Return the large count of a dealt round, or -1 when it breaks the rules
    integer function check_round(mode, target, pool)
        integer, intent(in) :: mode
        integer(int32), intent(in) :: target, pool(6)
        integer(int32) :: cards(4)
        integer :: small_seen(10), i, k
        logical :: large_seen(4)

        check_round = -1
        if (target < 100 .or. target > 999) return
        cards = large_numbers(mode)
        small_seen = 0
        large_seen = .false.
        do i = 1, 6
            if (pool(i) >= 1 .and. pool(i) <= 10) then
                ! Reject a small number after a large one since the pool lists small cards first
                if (any(large_seen)) return
                small_seen(pool(i)) = small_seen(pool(i)) + 1
                if (small_seen(pool(i)) > 2) return
            else
                k = findloc(cards, pool(i), dim=1)
                if (k == 0) return
                if (large_seen(k)) return
                large_seen(k) = .true.
            end if
        end do
        check_round = count(large_seen)
    end function check_round

    subroutine expect(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            print '(2a)', 'FAIL: ', what
            failures = failures + 1
        end if
    end subroutine expect

end program test_solver
