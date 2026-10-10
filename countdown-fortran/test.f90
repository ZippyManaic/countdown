! Check the solver against rounds with known answers
program test_solver
    use countdown_solver, only: solve_round
    use iso_fortran_env, only: int32
    implicit none
    integer(int32) :: value
    character(:), allocatable :: expr
    integer :: failures

    failures = 0
    call solve_round(125, [1, 5, 7, 3, 75, 50], value, expr)
    call expect(value == 125 .and. expr == '75 + 50', 'finds simplest solution')
    call solve_round(552, [8, 4, 2, 5, 100, 25], value, expr)
    call expect(value == 552, 'solves 552')
    call solve_round(974, [8, 8, 6, 8, 25, 100], value, expr)
    call expect(abs(value - 974) == 1, 'reports closest when unsolvable')
    if (failures > 0) stop 1, quiet=.true.
    print '(a)', 'all tests passed'

contains

    subroutine expect(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            print '(2a)', 'FAIL: ', what
            failures = failures + 1
        end if
    end subroutine expect

end program test_solver
