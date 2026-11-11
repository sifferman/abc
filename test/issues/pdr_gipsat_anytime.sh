#!/usr/bin/env bash
# "pdr -s" keeps one GipSAT solver per timeframe. Reducing the invariant drops a
# scratch timeframe, and the anytime schedule "-l" restarts the timeframes from
# zero, so the GipSAT solvers have to be dropped in step with the SAT solvers.
source "$(dirname "$0")/common.sh"
ulimit -c 0
# One latch that toggles from 0 and drives the only output, so the output is
# asserted in frame 1 and the run reaches frame 1 first.
printf 'aig 1 0 1 1 0\n3\n2\n' > toggle.aig
# "-l" and "-d" are the two callers that drop a scratch timeframe: the anytime
# schedule reduces the invariant after every timeframe, and "-d" reduces it once
# before dumping. Running each without "-s" covers the case of no GipSAT solver.
for solver in '-s' ''; do
    for reduce in '-l' '-d'; do
        run_abc "read_aiger toggle.aig; pdr $solver $reduce"
        expect_log 'was asserted in frame 1'
        echo "PASS: scratch timeframe, pdr ${solver:-no -s} $reduce"
    done
done
# An 8-bit counter asserts its output in frame 255, which takes much longer than
# the 1 ms per-output budget set by "-H 1", so the anytime schedule restarts the
# timeframes several times before the run finishes.
{
    echo '.model output_asserted_in_frame_255'
    echo '.outputs counter_is_all_ones'
    echo '.names bit0 next_bit0'
    echo '0 1'
    echo '.names bit0 carry0'
    echo '1 1'
    for bit in 1 2 3 4 5 6 7; do
        echo ".names bit$bit carry$((bit - 1)) next_bit$bit"
        echo '10 1'
        echo '01 1'
        echo ".names bit$bit carry$((bit - 1)) carry$bit"
        echo '11 1'
    done
    echo '.names carry7 counter_is_all_ones'
    echo '1 1'
    for bit in 0 1 2 3 4 5 6 7; do
        echo ".latch next_bit$bit bit$bit 0"
    done
    echo '.end'
} > counter.blif
for solver in '-s' ''; do
    run_abc "read_blif counter.blif; strash; pdr $solver -l -H 1"
    expect_log 'Starting new anytime pass'
    expect_log 'was asserted in frame 255'
    echo "PASS: anytime restart, pdr ${solver:-no -s} -l -H 1"
done
echo 'PASS: GipSAT solvers under the anytime schedule'
