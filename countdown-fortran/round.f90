! Deal Countdown rounds in the standard, cats and nasty-cats modes and read the mode from the command line
module countdown_round
    use iso_fortran_env, only: int32
    implicit none
    private
    public :: mode_standard, mode_cats, mode_nasty, random_large, usage, large_numbers, deal_round, parse_args

    integer, parameter :: mode_standard = 1, mode_cats = 2, mode_nasty = 3
    ! Mark a large count chosen at random rather than fixed on the command line
    integer, parameter :: random_large = -1
    character(*), parameter :: usage = 'usage: countdown [standard|cats|nasty] [LARGE]'
    ! Give nasty-cats the large cards of the 2010 specials
    integer(int32), parameter :: decks(4, 3) = reshape([25, 50, 75, 100, 25, 50, 75, 100, 12, 37, 62, 87], [4, 3])

contains

    ! Return the four large cards a mode deals from
    pure function large_numbers(mode) result(cards)
        integer, intent(in) :: mode
        integer(int32) :: cards(4)
        cards = decks(:, mode)
    end function large_numbers

    ! Deal a target and six numbers, small first, with large_count large numbers or a random count when it is random_large
    subroutine deal_round(mode, large_count, target, pool)
        integer, intent(in) :: mode, large_count
        integer(int32), intent(out) :: target, pool(6)
        integer(int32) :: small(20), large(4)
        integer :: count, i

        target = 100 + random_below(900)
        count = large_count
        if (count == random_large) then
            if (mode == mode_standard) then
                count = 1 + random_below(2)
            else
                count = random_below(5)
            end if
        end if

        ! Hold two cards of each small number to match the game's deck
        small = [(mod(i - 1, 10) + 1, i=1, 20)]
        call shuffle(small)
        ! Shuffle a copy since each large number appears only once in the game
        large = decks(:, mode)
        call shuffle(large)
        pool = [small(1:6 - count), large(1:count)]
    end subroutine deal_round

    ! Set the mode and fixed large count from the arguments after the program name and ok to whether they are valid
    subroutine parse_args(args, mode, large_count, ok)
        character(*), intent(in) :: args(:)
        integer, intent(out) :: mode, large_count
        logical, intent(out) :: ok
        integer :: n

        mode = mode_standard
        large_count = random_large
        ok = .false.
        if (size(args) > 2) return
        if (size(args) >= 1) then
            select case (args(1))
            case ('standard')
                mode = mode_standard
            case ('cats')
                mode = mode_cats
            case ('nasty')
                mode = mode_nasty
            case default
                return
            end select
        end if
        if (size(args) == 2) then
            ! Accept only a single digit so that signs and trailing text are rejected
            if (len_trim(args(2)) /= 1 .or. verify(args(2)(1:1), '0123456789') /= 0) return
            n = index('0123456789', args(2)(1:1)) - 1
            if (mode == mode_standard) then
                if (n < 1 .or. n > 2) return
            else
                if (n > 4) return
            end if
            large_count = n
        end if
        ok = .true.
    end subroutine parse_args

    ! Return a random integer from zero up to but not including n
    integer function random_below(n)
        integer, intent(in) :: n
        real :: r
        call random_number(r)
        random_below = min(int(r*n), n - 1)
    end function random_below

    ! Shuffle numbers in place with Fisher-Yates
    subroutine shuffle(items)
        integer(int32), intent(inout) :: items(:)
        integer :: i, j
        integer(int32) :: t
        do i = size(items), 2, -1
            j = 1 + random_below(i)
            t = items(i)
            items(i) = items(j)
            items(j) = t
        end do
    end subroutine shuffle

end module countdown_round
