       >>SOURCE FORMAT FREE
*> Work out the simplest Countdown expression that hits a target or gets closest to it
*> Keep hot paths to ADD, SUBTRACT, MOVE, comparisons and subscripts since GnuCOBOL compiles only those to native code
IDENTIFICATION DIVISION.
PROGRAM-ID. solve.

DATA DIVISION.
WORKING-STORAGE SECTION.
*> Hold the powers of two once since they never change between solves
01 powers-ready             PIC X VALUE "N".
01 powers.
   05 power-of-two          BINARY-LONG UNSIGNED OCCURS 32 TIMES.
*> Hold each subset's splits for the current pool size since they depend on nothing else and B-AND is not native
01 splits-for-n             BINARY-LONG UNSIGNED VALUE 0.
01 split-index.
   05 split-first           BINARY-LONG UNSIGNED OCCURS 256 TIMES.
   05 split-total           BINARY-LONG UNSIGNED OCCURS 256 TIMES.
01 split-list.
   05 split-pair OCCURS 3300 TIMES.
      10 sp-left            BINARY-LONG UNSIGNED.
      10 sp-right           BINARY-LONG UNSIGNED.
*> Hold whether each bit is set in each byte value for building the splits
01 bit-table.
   05 bit-row OCCURS 256 TIMES.
      10 bit-set            BINARY-CHAR UNSIGNED OCCURS 8 TIMES.
01 w-mask                   BINARY-LONG UNSIGNED.
01 w-left                   BINARY-LONG UNSIGNED.
01 w-right                  BINARY-LONG UNSIGNED.
01 w-rest                   BINARY-LONG UNSIGNED.
01 w-bit                    BINARY-LONG UNSIGNED.
01 w-inside                 PIC X.
01 w-next                   BINARY-LONG UNSIGNED.

LOCAL-STORAGE SECTION.
01 full                     BINARY-LONG UNSIGNED.
01 size-now                 BINARY-LONG UNSIGNED.
01 mask                     BINARY-LONG UNSIGNED.
01 left-mask                BINARY-LONG UNSIGNED.
01 right-mask               BINARY-LONG UNSIGNED.
01 i                        BINARY-LONG UNSIGNED.
01 j                        BINARY-LONG UNSIGNED.
01 k                        BINARY-LONG UNSIGNED.
01 m                        BINARY-LONG UNSIGNED.
01 solved                   PIC X.
01 a-value                  BINARY-LONG UNSIGNED.
01 b-value                  BINARY-LONG UNSIGNED.
01 v                        BINARY-LONG UNSIGNED.
01 twice                    BINARY-LONG UNSIGNED.
01 d                        BINARY-LONG UNSIGNED.
01 best-distance            BINARY-LONG UNSIGNED.
01 best-used                BINARY-LONG UNSIGNED.
01 whole-distance           BINARY-LONG UNSIGNED.
01 quotient                 BINARY-LONG UNSIGNED.
01 remainder-value          BINARY-LONG UNSIGNED.
01 product-limit            BINARY-LONG UNSIGNED.
01 search-limit             BINARY-LONG UNSIGNED.
01 stamp-ptr                USAGE POINTER.
01 stamp-size               BINARY-LONG UNSIGNED.
01 stamp-count              BINARY-LONG UNSIGNED.
01 cand-ptr                 USAGE POINTER.
01 grown-ptr                USAGE POINTER.
01 aux-ptr                  USAGE POINTER.
01 cand-cap                 BINARY-LONG UNSIGNED.
01 cand-count               BINARY-LONG UNSIGNED.
01 need                     BINARY-LONG UNSIGNED.
*> Pass the table size to calloc as the 64-bit size it expects
01 need-bytes               BINARY-DOUBLE UNSIGNED.
01 l-count                  BINARY-LONG UNSIGNED.
01 r-count                  BINARY-LONG UNSIGNED.
01 s-count                  BINARY-LONG UNSIGNED.
01 g-count                  BINARY-LONG UNSIGNED.
01 search-value             BINARY-LONG UNSIGNED.
01 found                    PIC X.
01 base                     BINARY-LONG UNSIGNED.
01 probe                    BINARY-LONG UNSIGNED.
01 step-k                   BINARY-LONG UNSIGNED.
01 top-step                 BINARY-LONG UNSIGNED.
*> Track each subset's allocated values with their count, size and largest possible value
01 subsets.
   05 subset OCCURS 255 TIMES.
      10 subset-ptr         USAGE POINTER.
      10 subset-len         BINARY-LONG UNSIGNED.
      10 subset-bits        BINARY-LONG UNSIGNED.
      10 subset-max         BINARY-LONG UNSIGNED.
01 largest-of-size.
   05 largest               BINARY-LONG UNSIGNED OCCURS 9 TIMES.
*> Assemble each new entry here before it is copied into the candidates
01 new-entry.
   05 ne-value              BINARY-LONG UNSIGNED.
   05 ne-op                 PIC X.
   05 ne-lmask              BINARY-CHAR UNSIGNED.
   05 ne-smask              BINARY-CHAR UNSIGNED.
   05 FILLER                PIC X.
   05 ne-larger             BINARY-LONG UNSIGNED.
   05 ne-smaller            BINARY-LONG UNSIGNED.
01 exact-entry.
   05 ex-value              BINARY-LONG UNSIGNED.
   05 ex-op                 PIC X.
   05 ex-lmask              BINARY-CHAR UNSIGNED.
   05 ex-smask              BINARY-CHAR UNSIGNED.
   05 FILLER                PIC X.
   05 ex-larger             BINARY-LONG UNSIGNED.
   05 ex-smaller            BINARY-LONG UNSIGNED.
01 best-entry.
   05 be-value              BINARY-LONG UNSIGNED.
   05 FILLER                PIC X(12).
01 whole-entry.
   05 wh-value              BINARY-LONG UNSIGNED.
   05 FILLER                PIC X(12).
*> Hold every number that combines with another to make the target
01 partner-list.
   05 partner-count         BINARY-LONG UNSIGNED.
   05 partner OCCURS 6 TIMES.
      10 partner-value      BINARY-LONG UNSIGNED.
      10 partner-op         PIC X.
01 fe-n                     BINARY-LONG UNSIGNED.
01 fe-best-a                BINARY-LONG UNSIGNED.
01 fe-best-b                BINARY-LONG UNSIGNED.
01 fe-best-op               PIC X.
*> Count each byte value for one radix pass then turn the counts into positions
01 radix-counts.
   05 radix-count           BINARY-LONG UNSIGNED OCCURS 256 TIMES.
01 radix-digit              BINARY-LONG UNSIGNED.
01 radix-byte               BINARY-CHAR UNSIGNED.
01 radix-sum                BINARY-LONG UNSIGNED.
01 radix-from-aux           PIC X.
*> Hold constants as fields since moving a literal into a binary field goes through the generic conversion
01 zero-value               BINARY-LONG UNSIGNED VALUE 0.
01 one-value                BINARY-LONG UNSIGNED VALUE 1.
01 two-value                BINARY-LONG UNSIGNED VALUE 2.
01 split-cursor             BINARY-LONG UNSIGNED.
01 split-end                BINARY-LONG UNSIGNED.
*> Multiply and divide with shifts made of additions since GnuCOBOL sends MULTIPLY and DIVIDE through decimal arithmetic
01 mul-x                    BINARY-LONG UNSIGNED.
01 mul-y                    BINARY-LONG UNSIGNED.
01 mul-out                  BINARY-LONG UNSIGNED.
01 div-n                    BINARY-LONG UNSIGNED.
01 div-d                    BINARY-LONG UNSIGNED.
01 div-out-q                BINARY-LONG UNSIGNED.
01 div-out-r                BINARY-LONG UNSIGNED.
01 bit-i                    BINARY-LONG UNSIGNED.
*> Keep one-byte copies of the masks so moving them into entries is a plain byte copy
01 mask-byte                BINARY-CHAR UNSIGNED.
01 left-byte                BINARY-CHAR UNSIGNED.
01 right-byte               BINARY-CHAR UNSIGNED.
*> Carry the product and the quotient and remainder forward as one operand steps through sorted values
01 product                  BINARY-LONG UNSIGNED.
01 fixed-operand                    BINARY-LONG UNSIGNED.
01 moving-operand                   BINARY-LONG UNSIGNED.
01 product-from             BINARY-LONG UNSIGNED.
01 step-size                     BINARY-LONG UNSIGNED.
01 step-limit               BINARY-LONG UNSIGNED.
01 t                        BINARY-LONG UNSIGNED.
01 div-from                 BINARY-LONG UNSIGNED.
01 div-q                    BINARY-LONG UNSIGNED.
01 div-r                    BINARY-LONG UNSIGNED.
01 render-pos               BINARY-SHORT UNSIGNED.
01 render-bracket           PIC X.

LINKAGE SECTION.
01 lk-target                BINARY-LONG UNSIGNED.
01 lk-pool.
   05 lk-pool-number        BINARY-LONG UNSIGNED OCCURS 6 TIMES.
01 lk-n                     BINARY-LONG UNSIGNED.
01 lk-out                   PIC X(128).
01 lk-value                 BINARY-LONG UNSIGNED.
01 lk-len                   BINARY-LONG UNSIGNED.
*> Mark each value with the mask of the subset that last made it so no clearing is needed between subsets
01 stamp-table BASED.
   05 stamp                 BINARY-CHAR UNSIGNED OCCURS 1 TO 2000000000 TIMES DEPENDING ON stamp-count.
*> Lay out every table of entries the same way so one block can be viewed through any of them
01 cand-table BASED.
   05 cand OCCURS 1 TO 100000000 TIMES DEPENDING ON cand-count.
      10 c-value            BINARY-LONG UNSIGNED.
      10 c-bytes REDEFINES c-value.
         15 c-byte          BINARY-CHAR UNSIGNED OCCURS 4 TIMES.
      10 FILLER             PIC X(12).
01 aux-table BASED.
   05 aux OCCURS 1 TO 100000000 TIMES DEPENDING ON cand-count.
      10 x-value            BINARY-LONG UNSIGNED.
      10 x-bytes REDEFINES x-value.
         15 x-byte          BINARY-CHAR UNSIGNED OCCURS 4 TIMES.
      10 FILLER             PIC X(12).
01 grown-table BASED.
   05 grown OCCURS 1 TO 100000000 TIMES DEPENDING ON g-count.
      10 FILLER             PIC X(16).
01 l-table BASED.
   05 l-entry OCCURS 1 TO 100000000 TIMES DEPENDING ON l-count.
      10 l-value            BINARY-LONG UNSIGNED.
      10 FILLER             PIC X(12).
01 r-table BASED.
   05 r-entry OCCURS 1 TO 100000000 TIMES DEPENDING ON r-count.
      10 r-value            BINARY-LONG UNSIGNED.
      10 FILLER             PIC X(12).
01 s-table BASED.
   05 s-entry OCCURS 1 TO 100000000 TIMES DEPENDING ON s-count.
      10 s-value            BINARY-LONG UNSIGNED.
      10 FILLER             PIC X(12).

PROCEDURE DIVISION USING lk-target lk-pool lk-n lk-out lk-value lk-len.
main-line.
    IF powers-ready = "N"
        MOVE 1 TO power-of-two(1)
        PERFORM VARYING i FROM 2 BY 1 UNTIL i > 32
            MOVE power-of-two(i - 1) TO power-of-two(i)
            ADD power-of-two(i - 1) TO power-of-two(i)
        END-PERFORM
        MOVE "Y" TO powers-ready
    END-IF
    MOVE power-of-two(lk-n + 1) TO full
    SUBTRACT 1 FROM full
    IF splits-for-n NOT = lk-n
        PERFORM build-split-cache
    END-IF
    *> Find the largest product with the target that still fits in 32 bits
    DIVIDE lk-target INTO 4294967295 GIVING product-limit
    INITIALIZE largest-of-size
    PERFORM VARYING mask FROM 1 BY 1 UNTIL mask > full
        PERFORM prepare-subset
    END-PERFORM
    MOVE 0 TO stamp-size
    SET stamp-ptr TO NULL
    MOVE 1024 TO cand-cap
    ALLOCATE cand-cap * 16 CHARACTERS RETURNING cand-ptr
    ALLOCATE cand-cap * 16 CHARACTERS RETURNING aux-ptr
    SET ADDRESS OF cand-table TO cand-ptr
    MOVE "N" TO solved

    *> Store each pool number as a one-number subset
    PERFORM VARYING i FROM 1 BY 1 UNTIL i > lk-n
        MOVE power-of-two(i) TO mask
        ALLOCATE 16 CHARACTERS INITIALIZED RETURNING subset-ptr(mask)
        MOVE 1 TO subset-len(mask) l-count
        SET ADDRESS OF l-table TO subset-ptr(mask)
        MOVE lk-pool-number(i) TO l-value(1)
        IF lk-pool-number(i) = lk-target AND solved = "N"
            MOVE l-entry(1) TO exact-entry
            MOVE "Y" TO solved
        END-IF
    END-PERFORM

    *> Work through subsets smallest first stopping at the first size that hits the target
    PERFORM VARYING size-now FROM 2 BY 1 UNTIL size-now > lk-n OR solved = "Y"
        *> Keep the lowest matching subset of this size to break ties the same way every run
        PERFORM VARYING mask FROM 1 BY 1 UNTIL mask > full OR solved = "Y"
            IF subset-bits(mask) = size-now
                PERFORM find-exact
            END-IF
        END-PERFORM
        *> Skip building the whole pool's values since no larger subset is made from them
        IF solved = "N" AND size-now < lk-n
            PERFORM reserve-stamps
            PERFORM VARYING mask FROM 1 BY 1 UNTIL mask > full
                IF subset-bits(mask) = size-now
                    PERFORM build-subset
                END-IF
            END-PERFORM
        END-IF
    END-PERFORM

    IF solved = "Y"
        MOVE exact-entry TO best-entry
    ELSE
        PERFORM find-closest
    END-IF

    *> Render without outer brackets which matches stripping them from the bracketed form
    MOVE SPACES TO lk-out
    MOVE 1 TO render-pos
    MOVE "N" TO render-bracket
    CALL "cd-render" USING subsets best-entry lk-out render-pos render-bracket
    MOVE render-pos TO lk-len
    SUBTRACT 1 FROM lk-len
    MOVE X"00" TO lk-out(render-pos:1)
    MOVE be-value TO lk-value

    PERFORM VARYING mask FROM 1 BY 1 UNTIL mask > full
        IF subset-ptr(mask) NOT = NULL
            FREE subset-ptr(mask)
        END-IF
    END-PERFORM
    IF stamp-ptr NOT = NULL
        CALL "free" USING BY VALUE stamp-ptr
    END-IF
    FREE cand-ptr
    FREE aux-ptr
    GOBACK.

*> Count the subset's numbers and work out its largest value since subtracting and dividing never exceed the larger operand
prepare-subset.
    SET subset-ptr(mask) TO NULL
    MOVE 0 TO subset-len(mask) subset-bits(mask) subset-max(mask)
    MOVE mask TO m
    PERFORM VARYING i FROM 32 BY -1 UNTIL i < 1
        IF m >= power-of-two(i)
            SUBTRACT power-of-two(i) FROM m
            ADD 1 TO subset-bits(mask)
            IF subset-bits(mask) = 1
                MOVE lk-pool-number(i) TO subset-max(mask)
            END-IF
        END-IF
    END-PERFORM
    IF subset-bits(mask) > 1
        MOVE 0 TO subset-max(mask)
        PERFORM first-split
        PERFORM UNTIL left-mask = 0
            MOVE subset-max(left-mask) TO a-value
            MOVE subset-max(right-mask) TO b-value
            MOVE a-value TO mul-x
            MOVE b-value TO mul-y
            PERFORM native-multiply
            MOVE mul-out TO v
            MOVE a-value TO twice
            ADD b-value TO twice
            IF twice > v
                MOVE twice TO v
            END-IF
            IF v > subset-max(mask)
                MOVE v TO subset-max(mask)
            END-IF
            PERFORM next-split
        END-PERFORM
    END-IF
    MOVE subset-bits(mask) TO k
    IF subset-max(mask) > largest(k)
        MOVE subset-max(mask) TO largest(k)
    END-IF.

*> Step left-mask to the next submask of mask in descending order and set right-mask to the rest
next-split.
    IF split-cursor >= split-end
        MOVE zero-value TO left-mask
    ELSE
        ADD 1 TO split-cursor
        MOVE sp-left(split-cursor) TO left-mask
        MOVE sp-right(split-cursor) TO right-mask
    END-IF.

*> Start stepping through the current mask's splits in the order (left - 1) & mask would visit them
first-split.
    MOVE split-first(mask) TO split-cursor
    MOVE split-cursor TO split-end
    ADD split-total(mask) TO split-end
    PERFORM next-split.

*> List every split with the smaller-numbered half on the left for each subset of the pool
build-split-cache.
    PERFORM VARYING w-mask FROM 0 BY 1 UNTIL w-mask > 255
        MOVE w-mask TO w-rest
        PERFORM VARYING w-bit FROM 8 BY -1 UNTIL w-bit < 1
            MOVE 0 TO bit-set(w-mask + 1, w-bit)
            IF w-rest >= power-of-two(w-bit)
                SUBTRACT power-of-two(w-bit) FROM w-rest
                MOVE 1 TO bit-set(w-mask + 1, w-bit)
            END-IF
        END-PERFORM
    END-PERFORM
    MOVE 0 TO w-next
    PERFORM VARYING w-mask FROM 1 BY 1 UNTIL w-mask > full
        MOVE w-next TO split-first(w-mask)
        MOVE 0 TO split-total(w-mask)
        PERFORM VARYING w-left FROM w-mask BY -1 UNTIL w-left < 2
            MOVE w-left TO w-rest
            SUBTRACT 1 FROM w-rest
            MOVE "Y" TO w-inside
            PERFORM VARYING w-bit FROM 1 BY 1 UNTIL w-bit > 8
                IF bit-set(w-rest + 1, w-bit) = 1 AND bit-set(w-mask + 1, w-bit) = 0
                    MOVE "N" TO w-inside
                    EXIT PERFORM
                END-IF
            END-PERFORM
            MOVE w-mask TO w-right
            SUBTRACT w-rest FROM w-right
            IF w-inside = "Y" AND w-rest < w-right
                ADD 1 TO w-next
                ADD 1 TO split-total(w-mask)
                MOVE w-rest TO sp-left(w-next)
                MOVE w-right TO sp-right(w-next)
            END-IF
        END-PERFORM
    END-PERFORM
    MOVE lk-n TO splits-for-n.

*> Set mul-out to mul-x times mul-y by doubling and adding over the bits of mul-y
native-multiply.
    MOVE zero-value TO mul-out
    *> Find the top bit by counting up since the multiplier is usually small
    MOVE one-value TO bit-i
    PERFORM UNTIL bit-i = 32 OR power-of-two(bit-i + 1) > mul-y
        ADD 1 TO bit-i
    END-PERFORM
    PERFORM VARYING bit-i FROM bit-i BY -1 UNTIL bit-i < 1
        ADD mul-out TO mul-out
        IF mul-y >= power-of-two(bit-i)
            SUBTRACT power-of-two(bit-i) FROM mul-y
            ADD mul-x TO mul-out
        END-IF
    END-PERFORM.

*> Set div-out-q and div-out-r to div-n divided by div-d with long division over the bits of div-n
native-divide.
    MOVE zero-value TO div-out-q div-out-r
    MOVE one-value TO bit-i
    PERFORM UNTIL bit-i = 32 OR power-of-two(bit-i + 1) > div-n
        ADD 1 TO bit-i
    END-PERFORM
    PERFORM VARYING bit-i FROM bit-i BY -1 UNTIL bit-i < 1
        ADD div-out-r TO div-out-r
        ADD div-out-q TO div-out-q
        IF div-n >= power-of-two(bit-i)
            SUBTRACT power-of-two(bit-i) FROM div-n
            ADD 1 TO div-out-r
        END-IF
        IF div-out-r >= div-d
            SUBTRACT div-d FROM div-out-r
            ADD 1 TO div-out-q
        END-IF
    END-PERFORM.

*> Make the stamp table cover every value up to the largest one subsets of this size can make
reserve-stamps.
    MOVE largest(size-now) TO need
    ADD 1 TO need
    IF need > stamp-size
        IF stamp-ptr NOT = NULL
            CALL "free" USING BY VALUE stamp-ptr
        END-IF
        *> Replace rather than copy since stamps from smaller subsets never match a new mask
        *> Use calloc since large zeroed blocks come straight from the system and cost only the pages touched
        MOVE need TO need-bytes
        CALL "calloc" USING BY VALUE need-bytes BY VALUE 1 RETURNING stamp-ptr
        IF stamp-ptr = NULL
            DISPLAY "calloc failed" UPON SYSERR
            STOP RUN RETURNING 2
        END-IF
        MOVE need TO stamp-size stamp-count
        SET ADDRESS OF stamp-table TO stamp-ptr
    END-IF.

*> Point the left and right tables at the halves of the current split
load-halves.
    SET ADDRESS OF l-table TO subset-ptr(left-mask)
    MOVE subset-len(left-mask) TO l-count
    SET ADDRESS OF r-table TO subset-ptr(right-mask)
    MOVE subset-len(right-mask) TO r-count.

build-subset.
    MOVE zero-value TO cand-count
    MOVE mask TO mask-byte
    PERFORM first-split
    PERFORM UNTIL left-mask = 0
        *> Visit each split once rather than once per ordering
        IF left-mask < right-mask
            PERFORM load-halves
            MOVE left-mask TO left-byte
            MOVE right-mask TO right-byte
            PERFORM VARYING i FROM one-value BY 1 UNTIL i > l-count
                MOVE l-value(i) TO a-value
                *> Pair with right values up to a first where a is the larger and ties go left
                MOVE left-byte TO ne-lmask
                MOVE right-byte TO ne-smask
                MOVE a-value TO ne-larger
                MOVE zero-value TO product product-from
                PERFORM VARYING j FROM one-value BY 1 UNTIL j > r-count
                    MOVE r-value(j) TO b-value
                    IF b-value > a-value
                        EXIT PERFORM
                    END-IF
                    MOVE b-value TO ne-smaller
                    PERFORM emit-left-larger
                END-PERFORM
                *> Pair with the remaining larger right values where a is the smaller
                MOVE right-byte TO ne-lmask
                MOVE left-byte TO ne-smask
                MOVE a-value TO ne-smaller
                MOVE zero-value TO product product-from div-from div-q div-r
                *> Allow sixteen subtractions per step by doubling four times since MULTIPLY is not native
                MOVE a-value TO step-limit
                ADD step-limit TO step-limit
                ADD step-limit TO step-limit
                ADD step-limit TO step-limit
                ADD step-limit TO step-limit
                PERFORM UNTIL j > r-count
                    MOVE r-value(j) TO ne-larger
                    PERFORM emit-right-larger
                    ADD 1 TO j
                END-PERFORM
            END-PERFORM
        END-IF
        PERFORM next-split
    END-PERFORM
    PERFORM sort-candidates
    ALLOCATE cand-count * 16 CHARACTERS RETURNING subset-ptr(mask)
    MOVE cand-count TO subset-len(mask) g-count
    SET ADDRESS OF grown-table TO subset-ptr(mask)
    MOVE cand-table TO grown-table.

*> Move the product on to the fixed operand times the moving operand by adding the fixed operand once per step when the step is small
advance-product.
    MOVE moving-operand TO step-size
    SUBTRACT product-from FROM step-size
    IF step-size <= 16
        PERFORM VARYING t FROM one-value BY 1 UNTIL t > step-size
            ADD fixed-operand TO product
        END-PERFORM
    ELSE
        MOVE fixed-operand TO mul-x
        MOVE moving-operand TO mul-y
        PERFORM native-multiply
        MOVE mul-out TO product
    END-IF
    MOVE moving-operand TO product-from.

*> Emit every legal result of a larger left value and a right value no larger than it
emit-left-larger.
    MOVE ne-larger TO v
    ADD ne-smaller TO v
    MOVE "+" TO ne-op
    PERFORM keep-if-new
    *> Skip a zero result since every intermediate value must be a positive integer
    IF ne-larger NOT = ne-smaller
        MOVE ne-larger TO v
        SUBTRACT ne-smaller FROM v
        MOVE "-" TO ne-op
        PERFORM keep-if-new
    END-IF
    *> Skip multiplying and dividing by one as they never produce a new value
    IF ne-smaller NOT = 1
        MOVE ne-larger TO fixed-operand
        MOVE ne-smaller TO moving-operand
        PERFORM advance-product
        MOVE product TO v
        MOVE "*" TO ne-op
        PERFORM keep-if-new
        *> Divide only when the quotient could be one from equal operands or at least two
        MOVE ne-smaller TO twice
        ADD ne-smaller TO twice
        IF ne-larger = ne-smaller OR ne-larger >= twice
            MOVE ne-larger TO div-n
            MOVE ne-smaller TO div-d
            PERFORM native-divide
            MOVE div-out-q TO quotient
            MOVE div-out-r TO remainder-value
            IF remainder-value = 0
                MOVE quotient TO v
                MOVE "/" TO ne-op
                PERFORM keep-if-new
            END-IF
        END-IF
    END-IF.

*> Emit every legal result of a larger right value and the fixed smaller left value
emit-right-larger.
    MOVE ne-larger TO v
    ADD ne-smaller TO v
    MOVE "+" TO ne-op
    PERFORM keep-if-new
    MOVE ne-larger TO v
    SUBTRACT ne-smaller FROM v
    MOVE "-" TO ne-op
    PERFORM keep-if-new
    IF ne-smaller NOT = 1
        MOVE ne-smaller TO fixed-operand
        MOVE ne-larger TO moving-operand
        PERFORM advance-product
        MOVE product TO v
        MOVE "*" TO ne-op
        PERFORM keep-if-new
        *> Carry the quotient and remainder forward since the divisor stays fixed while the dividend rises
        MOVE ne-larger TO step-size
        SUBTRACT div-from FROM step-size
        IF step-size <= step-limit
            ADD step-size TO div-r
            PERFORM UNTIL div-r < ne-smaller
                SUBTRACT ne-smaller FROM div-r
                ADD 1 TO div-q
            END-PERFORM
        ELSE
            MOVE ne-larger TO div-n
            MOVE ne-smaller TO div-d
            PERFORM native-divide
            MOVE div-out-q TO div-q
            MOVE div-out-r TO div-r
        END-IF
        MOVE ne-larger TO div-from
        IF div-r = 0
            MOVE div-q TO v
            MOVE "/" TO ne-op
            PERFORM keep-if-new
        END-IF
    END-IF.

*> Keep the value in v only if this subset has not made it yet so duplicates never reach the sort
keep-if-new.
    IF stamp(v + 1) NOT = mask-byte
        MOVE mask-byte TO stamp(v + 1)
        IF cand-count = cand-cap
            PERFORM grow-candidates
        END-IF
        ADD 1 TO cand-count
        MOVE v TO ne-value
        MOVE new-entry TO cand(cand-count)
    END-IF.

*> Double the candidate buffers keeping the values already collected
grow-candidates.
    ALLOCATE cand-cap * 32 CHARACTERS RETURNING grown-ptr
    MOVE cand-count TO g-count
    SET ADDRESS OF grown-table TO grown-ptr
    MOVE cand-table TO grown-table
    FREE cand-ptr
    FREE aux-ptr
    SET cand-ptr TO grown-ptr
    SET ADDRESS OF cand-table TO cand-ptr
    ADD cand-cap TO cand-cap
    ALLOCATE cand-cap * 16 CHARACTERS RETURNING aux-ptr.

*> Sort the candidates by value with insertion for a few and a byte radix sort otherwise
sort-candidates.
    IF cand-count < 16
        PERFORM VARYING i FROM two-value BY 1 UNTIL i > cand-count
            MOVE cand(i) TO new-entry
            MOVE i TO j
            PERFORM UNTIL j = 1
                IF c-value(j - 1) <= ne-value
                    EXIT PERFORM
                END-IF
                MOVE cand(j - 1) TO cand(j)
                SUBTRACT 1 FROM j
            END-PERFORM
            MOVE new-entry TO cand(j)
        END-PERFORM
    ELSE
        SET ADDRESS OF aux-table TO aux-ptr
        MOVE "N" TO radix-from-aux
        PERFORM VARYING radix-digit FROM one-value BY 1 UNTIL radix-digit > 4
            PERFORM radix-pass
        END-PERFORM
        *> Copy back when an odd number of passes left the result in the auxiliary buffer
        IF radix-from-aux = "Y"
            MOVE aux-table TO cand-table
        END-IF
    END-IF.

*> Distribute the candidates by one byte of their values skipping a byte every value shares
radix-pass.
    INITIALIZE radix-counts
    IF radix-from-aux = "N"
        PERFORM VARYING i FROM one-value BY 1 UNTIL i > cand-count
            ADD 1 TO radix-count(c-byte(i, radix-digit) + 1)
        END-PERFORM
        MOVE c-byte(1, radix-digit) TO radix-byte
    ELSE
        PERFORM VARYING i FROM one-value BY 1 UNTIL i > cand-count
            ADD 1 TO radix-count(x-byte(i, radix-digit) + 1)
        END-PERFORM
        MOVE x-byte(1, radix-digit) TO radix-byte
    END-IF
    IF radix-count(radix-byte + 1) NOT = cand-count
        MOVE one-value TO radix-sum
        PERFORM VARYING k FROM one-value BY 1 UNTIL k > 256
            MOVE radix-count(k) TO m
            MOVE radix-sum TO radix-count(k)
            ADD m TO radix-sum
        END-PERFORM
        IF radix-from-aux = "N"
            PERFORM VARYING i FROM one-value BY 1 UNTIL i > cand-count
                MOVE c-byte(i, radix-digit) TO radix-byte
                MOVE radix-count(radix-byte + 1) TO k
                MOVE cand(i) TO aux(k)
                ADD 1 TO radix-count(radix-byte + 1)
            END-PERFORM
            MOVE "Y" TO radix-from-aux
        ELSE
            PERFORM VARYING i FROM one-value BY 1 UNTIL i > cand-count
                MOVE x-byte(i, radix-digit) TO radix-byte
                MOVE radix-count(radix-byte + 1) TO k
                MOVE aux(i) TO cand(k)
                ADD 1 TO radix-count(radix-byte + 1)
            END-PERFORM
            MOVE "N" TO radix-from-aux
        END-IF
    END-IF.

*> Fill the partner list with every number that combines with fe-n to make the target in operator order
find-partners.
    MOVE zero-value TO partner-count
    IF lk-target > fe-n
        ADD 1 TO partner-count
        MOVE lk-target TO partner-value(partner-count)
        SUBTRACT fe-n FROM partner-value(partner-count)
        MOVE "+" TO partner-op(partner-count)
    END-IF
    IF fe-n > lk-target
        ADD 1 TO partner-count
        MOVE fe-n TO partner-value(partner-count)
        SUBTRACT lk-target FROM partner-value(partner-count)
        MOVE "-" TO partner-op(partner-count)
    END-IF
    ADD 1 TO partner-count
    MOVE fe-n TO partner-value(partner-count)
    ADD lk-target TO partner-value(partner-count)
    MOVE "-" TO partner-op(partner-count)
    *> Divide only when the quotient could be at least two since neither operand may be one
    MOVE fe-n TO twice
    ADD fe-n TO twice
    IF fe-n NOT = 1 AND twice <= lk-target
        MOVE lk-target TO div-n
        MOVE fe-n TO div-d
        PERFORM native-divide
        MOVE div-out-q TO quotient
        MOVE div-out-r TO remainder-value
        IF remainder-value = 0
            ADD 1 TO partner-count
            MOVE quotient TO partner-value(partner-count)
            MOVE "*" TO partner-op(partner-count)
        END-IF
    END-IF
    MOVE lk-target TO twice
    ADD lk-target TO twice
    IF fe-n >= twice
        MOVE fe-n TO div-n
        MOVE lk-target TO div-d
        PERFORM native-divide
        MOVE div-out-q TO quotient
        MOVE div-out-r TO remainder-value
        IF remainder-value = 0
            ADD 1 TO partner-count
            MOVE quotient TO partner-value(partner-count)
            MOVE "/" TO partner-op(partner-count)
        END-IF
    END-IF
    *> Skip a product larger than any value in the searched half
    IF fe-n NOT = 1 AND fe-n <= search-limit
        ADD 1 TO partner-count
        MOVE fe-n TO mul-x
        MOVE lk-target TO mul-y
        PERFORM native-multiply
        MOVE mul-out TO partner-value(partner-count)
        MOVE "/" TO partner-op(partner-count)
    END-IF.

*> Bound the values whose product with the target could be in the search table once per split
set-search-limit.
    DIVIDE s-value(s-count) BY lk-target GIVING search-limit
    IF search-limit > product-limit
        MOVE product-limit TO search-limit
    END-IF.

*> Set found when search-value is among the search table's values using steps of powers of two
lookup.
    MOVE "N" TO found
    IF search-value < s-value(1) OR search-value > s-value(s-count)
        EXIT PARAGRAPH
    END-IF
    *> Start from the largest power of two within the count so every probe stays inside the table
    MOVE one-value TO top-step
    PERFORM UNTIL power-of-two(top-step + 1) > s-count
        ADD 1 TO top-step
    END-PERFORM
    MOVE zero-value TO base
    PERFORM VARYING step-k FROM top-step BY -1 UNTIL step-k < 1
        MOVE base TO probe
        ADD power-of-two(step-k) TO probe
        IF probe <= s-count
            IF s-value(probe) <= search-value
                MOVE probe TO base
            END-IF
        END-IF
    END-PERFORM
    IF base > 0
        IF s-value(base) = search-value
            MOVE "Y" TO found
        END-IF
    END-IF.

*> Find how the target is first made from a subset without building all of its values
find-exact.
    PERFORM first-split
    PERFORM UNTIL left-mask = 0 OR solved = "Y"
        *> Visit splits in the same order as building so the same origin wins
        IF left-mask < right-mask
            PERFORM load-halves
            *> Keep the lowest pair as building would since partners come in operator order
            MOVE 4294967295 TO fe-best-a fe-best-b
            MOVE SPACE TO fe-best-op
            IF l-count <= r-count
                *> Take the first left value with any partner on the right since left values ascend
                SET ADDRESS OF s-table TO subset-ptr(right-mask)
                MOVE r-count TO s-count
                PERFORM set-search-limit
                PERFORM VARYING i FROM one-value BY 1 UNTIL i > l-count OR fe-best-op NOT = SPACE
                    MOVE l-value(i) TO fe-n
                    PERFORM find-partners
                    PERFORM VARYING k FROM one-value BY 1 UNTIL k > partner-count
                        IF partner-value(k) < fe-best-b
                            MOVE partner-value(k) TO search-value
                            PERFORM lookup
                            IF found = "Y"
                                MOVE fe-n TO fe-best-a
                                MOVE partner-value(k) TO fe-best-b
                                MOVE partner-op(k) TO fe-best-op
                            END-IF
                        END-IF
                    END-PERFORM
                END-PERFORM
            ELSE
                SET ADDRESS OF s-table TO subset-ptr(left-mask)
                MOVE l-count TO s-count
                PERFORM set-search-limit
                PERFORM VARYING i FROM one-value BY 1 UNTIL i > r-count
                    MOVE r-value(i) TO fe-n
                    PERFORM find-partners
                    PERFORM VARYING k FROM one-value BY 1 UNTIL k > partner-count
                        IF partner-value(k) < fe-best-a
                            MOVE partner-value(k) TO search-value
                            PERFORM lookup
                            IF found = "Y"
                                MOVE partner-value(k) TO fe-best-a
                                MOVE fe-n TO fe-best-b
                                MOVE partner-op(k) TO fe-best-op
                            END-IF
                        END-IF
                    END-PERFORM
                END-PERFORM
            END-IF
            IF fe-best-op NOT = SPACE
                MOVE lk-target TO ex-value
                MOVE fe-best-op TO ex-op
                IF fe-best-a >= fe-best-b
                    MOVE left-mask TO ex-lmask
                    MOVE fe-best-a TO ex-larger
                    MOVE right-mask TO ex-smask
                    MOVE fe-best-b TO ex-smaller
                ELSE
                    MOVE right-mask TO ex-lmask
                    MOVE fe-best-b TO ex-larger
                    MOVE left-mask TO ex-smask
                    MOVE fe-best-a TO ex-smaller
                END-IF
                MOVE "Y" TO solved
            END-IF
        END-IF
        PERFORM next-split
    END-PERFORM.

*> Set d to the distance between v and the target
distance-to-target.
    IF v >= lk-target
        MOVE v TO d
        SUBTRACT lk-target FROM d
    ELSE
        MOVE lk-target TO d
        SUBTRACT v FROM d
    END-IF.

find-closest.
    *> Rank by distance from the target then by how many numbers are used so the simplest answer wins
    MOVE 4294967295 TO best-distance
    MOVE 99 TO best-used
    *> Include a one-number pool here since the whole-pool pass below needs at least two numbers
    PERFORM VARYING mask FROM 1 BY 1 UNTIL mask > full OR (mask = full AND lk-n > 1)
        IF subset-len(mask) > 0
            SET ADDRESS OF l-table TO subset-ptr(mask)
            MOVE subset-len(mask) TO l-count
            PERFORM VARYING i FROM one-value BY 1 UNTIL i > l-count
                MOVE l-value(i) TO v
                PERFORM distance-to-target
                IF d < best-distance OR (d = best-distance AND subset-bits(mask) < best-used)
                    MOVE l-entry(i) TO best-entry
                    MOVE d TO best-distance
                    MOVE subset-bits(mask) TO best-used
                END-IF
            END-PERFORM
        END-IF
    END-PERFORM
    *> Check the whole pool's values as they are made since no larger subset is built from them
    IF lk-n > 1
        MOVE 4294967295 TO whole-distance wh-value
        MOVE full TO mask
        PERFORM first-split
        PERFORM UNTIL left-mask = 0
            IF left-mask < right-mask
                PERFORM load-halves
                PERFORM VARYING i FROM one-value BY 1 UNTIL i > l-count
                    MOVE l-value(i) TO a-value
                    MOVE left-mask TO ne-lmask
                    MOVE right-mask TO ne-smask
                    MOVE a-value TO ne-larger
                    PERFORM VARYING j FROM one-value BY 1 UNTIL j > r-count
                        MOVE r-value(j) TO b-value
                        IF b-value > a-value
                            EXIT PERFORM
                        END-IF
                        MOVE b-value TO ne-smaller
                        PERFORM check-results
                    END-PERFORM
                    MOVE right-mask TO ne-lmask
                    MOVE left-mask TO ne-smask
                    MOVE a-value TO ne-smaller
                    PERFORM UNTIL j > r-count
                        MOVE r-value(j) TO ne-larger
                        PERFORM check-results
                        ADD 1 TO j
                    END-PERFORM
                END-PERFORM
            END-IF
            PERFORM next-split
        END-PERFORM
        *> Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
        IF whole-distance < best-distance
            MOVE whole-entry TO best-entry
        END-IF
    END-IF.

*> Check every legal result of ne-larger and ne-smaller against the whole pool's best
check-results.
    MOVE ne-larger TO v
    ADD ne-smaller TO v
    MOVE "+" TO ne-op
    PERFORM keep-if-closer
    IF ne-larger NOT = ne-smaller
        MOVE ne-larger TO v
        SUBTRACT ne-smaller FROM v
        MOVE "-" TO ne-op
        PERFORM keep-if-closer
    END-IF
    IF ne-smaller NOT = 1
        MOVE ne-larger TO mul-x
        MOVE ne-smaller TO mul-y
        PERFORM native-multiply
        MOVE mul-out TO v
        MOVE "*" TO ne-op
        PERFORM keep-if-closer
        MOVE ne-smaller TO twice
        ADD ne-smaller TO twice
        IF ne-larger = ne-smaller OR ne-larger >= twice
            MOVE ne-larger TO div-n
            MOVE ne-smaller TO div-d
            PERFORM native-divide
            MOVE div-out-q TO quotient
            MOVE div-out-r TO remainder-value
            IF remainder-value = 0
                MOVE quotient TO v
                MOVE "/" TO ne-op
                PERFORM keep-if-closer
            END-IF
        END-IF
    END-IF.

*> Keep v as the whole pool's best if it is closer to the target or equally close and lower
keep-if-closer.
    PERFORM distance-to-target
    IF d < whole-distance OR (d = whole-distance AND v < wh-value)
        MOVE v TO ne-value
        MOVE new-entry TO whole-entry
        MOVE d TO whole-distance
    END-IF.

END PROGRAM solve.

*> Write the expression for an entry following its origins back to the pool with brackets when asked
IDENTIFICATION DIVISION.
PROGRAM-ID. cd-render RECURSIVE.

DATA DIVISION.
LOCAL-STORAGE SECTION.
01 digits                   PIC Z(9)9.
01 child-bracket            PIC X VALUE "Y".
01 child-entry              PIC X(16).
01 lo                       BINARY-LONG UNSIGNED.
01 hi                       BINARY-LONG UNSIGNED.
01 mid                      BINARY-LONG UNSIGNED.
01 t-count                  BINARY-LONG UNSIGNED.
01 wanted                   BINARY-LONG UNSIGNED.
01 wanted-mask              BINARY-LONG UNSIGNED.

LINKAGE SECTION.
01 lk-subsets.
   05 lk-subset OCCURS 255 TIMES.
      10 lk-subset-ptr      USAGE POINTER.
      10 lk-subset-len      BINARY-LONG UNSIGNED.
      10 lk-subset-bits     BINARY-LONG UNSIGNED.
      10 lk-subset-max      BINARY-LONG UNSIGNED.
01 lk-entry.
   05 en-value              BINARY-LONG UNSIGNED.
   05 en-op                 PIC X.
   05 en-lmask              BINARY-CHAR UNSIGNED.
   05 en-smask              BINARY-CHAR UNSIGNED.
   05 FILLER                PIC X.
   05 en-larger             BINARY-LONG UNSIGNED.
   05 en-smaller            BINARY-LONG UNSIGNED.
01 lk-out                   PIC X(128).
01 lk-pos                   BINARY-SHORT UNSIGNED.
01 lk-bracket               PIC X.
01 t-table BASED.
   05 t-entry OCCURS 1 TO 100000000 TIMES DEPENDING ON t-count.
      10 t-value            BINARY-LONG UNSIGNED.
      10 FILLER             PIC X(12).

PROCEDURE DIVISION USING lk-subsets lk-entry lk-out lk-pos lk-bracket.
    *> Treat a missing operator as a pool number
    IF en-op = LOW-VALUE OR en-op = SPACE
        MOVE en-value TO digits
        STRING FUNCTION TRIM(digits LEADING) DELIMITED BY SIZE INTO lk-out WITH POINTER lk-pos
        GOBACK
    END-IF
    IF lk-bracket = "Y"
        STRING "(" DELIMITED BY SIZE INTO lk-out WITH POINTER lk-pos
    END-IF
    MOVE en-lmask TO wanted-mask
    MOVE en-larger TO wanted
    PERFORM find-child
    CALL "cd-render" USING lk-subsets child-entry lk-out lk-pos child-bracket
    STRING " " en-op " " DELIMITED BY SIZE INTO lk-out WITH POINTER lk-pos
    MOVE en-smask TO wanted-mask
    MOVE en-smaller TO wanted
    PERFORM find-child
    CALL "cd-render" USING lk-subsets child-entry lk-out lk-pos child-bracket
    IF lk-bracket = "Y"
        STRING ")" DELIMITED BY SIZE INTO lk-out WITH POINTER lk-pos
    END-IF
    GOBACK.

*> Copy the entry for the wanted value from the wanted subset into child-entry
find-child.
    SET ADDRESS OF t-table TO lk-subset-ptr(wanted-mask)
    MOVE lk-subset-len(wanted-mask) TO t-count
    MOVE 1 TO lo
    MOVE t-count TO hi
    PERFORM UNTIL lo >= hi
        COMPUTE mid = (lo + hi) / 2
        IF t-value(mid) < wanted
            COMPUTE lo = mid + 1
        ELSE
            MOVE mid TO hi
        END-IF
    END-PERFORM
    MOVE t-entry(lo) TO child-entry.

END PROGRAM cd-render.
