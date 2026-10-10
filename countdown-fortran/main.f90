! Generate a Countdown numbers round and work out whether it can be solved
program countdown
    use countdown_solver, only: solve_round
    use iso_fortran_env, only: int32
    implicit none
    integer(int32), parameter :: large_numbers(4) = [25, 50, 75, 100]
    integer(int32) :: target, value, small(20), large(4), pool(6)
    integer :: large_count, i
    character(:), allocatable :: expr

    call random_init(repeatable=.false., image_distinct=.true.)
    target = 100 + random_below(900)
    large_count = 1 + random_below(2)

    ! Hold two cards of each small number to match the game's deck
    small = [(mod(i - 1, 10) + 1, i=1, 20)]
    call shuffle(small)
    ! Shuffle a copy since each large number appears only once in the game
    large = large_numbers
    call shuffle(large)
    pool = [small(1:6 - large_count), large(1:large_count)]

    write (*, '(a, i0)') 'Target: ', target
    write (*, '(a)', advance='no') 'Pool:  '
    do i = 1, 6
        write (*, '(1x, i0)', advance='no') pool(i)
    end do
    write (*, *)

    call solve_round(target, pool, value, expr)
    if (value == target) then
        write (*, '(a, a, a, i0)') 'Solved: ', expr, ' = ', value
    else
        write (*, '(a, a, a, i0, a, i0, a)') 'No exact solution, closest is ', expr, ' = ', value, &
            ' (', abs(value - target), ' away)'
        stop 1, quiet=.true.
    end if

contains

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

end program countdown
