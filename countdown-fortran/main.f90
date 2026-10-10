! Generate a Countdown numbers round and work out whether it can be solved
program countdown
    use countdown_round, only: deal_round, parse_args, usage
    use countdown_solver, only: solve_round
    use iso_fortran_env, only: int32, error_unit
    implicit none
    integer(int32) :: target, value, pool(6)
    integer :: mode, large_count, i, length, status
    character(8), allocatable :: args(:)
    character(:), allocatable :: expr
    logical :: ok

    ! Keep at most three arguments since the parser rejects any more than two
    allocate (args(min(command_argument_count(), 3)))
    do i = 1, size(args)
        call get_command_argument(i, args(i), length, status)
        ! Replace an argument that does not fit or ends in spaces with one the parser rejects
        if (status /= 0 .or. len_trim(args(i)) /= length) args(i) = '?'
    end do
    call parse_args(args, mode, large_count, ok)
    if (.not. ok) then
        write (error_unit, '(a)') usage
        stop 2, quiet=.true.
    end if

    call random_init(repeatable=.false., image_distinct=.true.)
    call deal_round(mode, large_count, target, pool)

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

end program countdown
