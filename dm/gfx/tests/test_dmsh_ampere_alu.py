#!/usr/bin/env python3
"""Ampere ALU instructions through the offline translator (dmsh_xlate, arch sm86), on registers the translator cannot fold, their result stored to shared memory so
that it is kept: BREV, BMSK, F2IP, UIMAD with an immediate in C, and HADD2 / HMUL2 with an immediate (test_dmsh_ampere_mem.py's Pokopia class has those two on constants, a negative immediate's sign, F2FP.MERGE_C,
F2I from a half, UP2UR, MEMBAR and ERRBAR). Needs DMSH_TEST_XLATE (the translator) like the other translator tests."""
import re, sys, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_dmsh_ampere_mem import EXIT, Translated, inst

STORE = (0x000fe8000000c800, 0x0000080609008388)   # STS.U32 [R9 * 16 + 8], R6 (Mario Kart World f94552a2a2bff505): the sink, R9 the thread index


def uldc(ur, bank, offset): return (0x000fe20000000800, 0x7ab9 | ur << 16 | offset << 38 | bank << 54)   # ULDC URd, c[bank][offset]
def waiting(i): return (i[0] | 0x3f << 52, i[1])   # the instruction waits on every scoreboard (control bits 116..121): it reads what an S2R before it wrote
def s2r_tid(rd): return (0x000e260000002100, 0x0000000000007919 | rd << 16)   # S2R Rd, SR_TID.X (Mario Kart World's encoding, write barrier 0)


class Alu(Translated):
    def kept(self, *code, srcs=()):
        """code between S2R R9 (and each register of srcs) = the thread index and the store of R6"""
        pre = b''.join(inst(*s2r_tid(r)) for r in (9, *srcs))
        body = b''.join(inst(*waiting(i)) for i in code)
        return self.translate(pre + body + inst(*waiting(STORE)) + inst(*EXIT), shared=0x1000)


class Brev(Alu):
    BREV = (0x001e240000000000, 0x0000001300067301)   # BREV R6, R19 (Pokémon Pokopia 6e8db04c25a53d8c, whose destination is R3)

    def test_reverses_the_bits(self):
        self.assertIn('reverse_bits', self.kept(self.BREV, srcs=(19,)))


class CarriesAndModifiers(Alu):
    """Constant inputs the translator folds, the result stored: IADD3's two carry predicates (sum >= 2^32 and sum >= 2 * 2^32, Mesa NAK's OpIAdd3 fold, checked on
    hardware), PLOP3's second table on the sources as they were, POPC / FLO with an immediate whose top bit (63) is no bitwise not, LEA.HI.SX32's sign-extended high
    word and LEA's negated B (~B + 1 with its carry; with .X the bitwise not). Encodings built for the test, each checked with nvdisasm 13.5 (sm_86)"""
    SEL_P0 = (0x000fc200040000ff, 0x00000001ff067807)   # SEL R6, RZ, 0x1, !P0: R6 = P0 ? 1 : 0

    def stored(self, *code):
        m = re.findall(r'\] = (\w+);', self.kept(*code))
        return m[-1] if m else None

    def test_popc_immediate_top_bit_is_no_not(self):
        self.assertEqual(self.stored((0x000fc20000000000, 0x800000ffff067909)), '9u')    # POPC R6, 0x800000ff

    def test_flo_immediate_top_bit_is_no_not(self):
        msl = self.kept((0x000fc200000e0000, 0x800400ffff067900))                         # FLO.U32 R6, 0x800400ff
        self.assertIn('spvFindUMSB(2147746047u)', msl)                                    # 0x800400ff itself, not its bitwise not

    def test_iadd3_carry_of_two_sets_both_predicates(self):
        iadd3 = (0x000fc2000791e9ff, 0xffffffffff077810)                                  # IADD3 R7, P0, P1, -RZ, -0x1, -RZ: 2^32 + 0xffffffff + 2^32
        self.assertEqual(self.stored(iadd3, self.SEL_P0), '1u')

    def test_plop3_second_table_reads_the_old_source(self):
        isetp = (0x000fc20003f42070, 0x000000ffff00720c)                                  # ISETP.EQ.U32.AND P2, PT, RZ, RZ, PT: P2 = true
        plop3 = (0x000fc2000104e070, 0x0000000000f0781c)                                  # PLOP3.LUT P2, P0, P2, PT, PT, 0x0, 0xf0: P2 = false, P0 = the old P2
        self.assertEqual(self.stored(isetp, plop3, self.SEL_P0), '1u')

    def test_lea_hi_sx32_sign_extends(self):
        mov = (0x000fc20000000fff, 0x80000000ff057802)                                    # MOV R5, 0x80000000
        lea = (0x000fc200078f0aff, 0x000000ff05067211)                                    # LEA.HI.SX32 R6, R5, RZ, 0x1: (0xffffffff:R5) >> 31
        self.assertEqual(self.stored(mov, lea), '4294967295u')

    def test_lea_negated_zero_b_carries(self):
        lea = (0x000fc200078000ff, 0x800000ffff067211)                                    # LEA R6, P0, RZ, -RZ, 0x0: ~0 + 1 carries out
        self.assertEqual(self.stored(lea, self.SEL_P0), '1u')

    def test_lea_x_not_b(self):
        lea = (0x000fc200038e04ff, 0x800000ffff067211)                                    # LEA.X R6, RZ, ~RZ, 0x0, PT: 0 + 0xffffffff + 1
        self.assertEqual(self.stored(lea), '0u')


class HalfImmediate(Alu):
    """HADD2 / HMUL2 Rd, Ra, imm (form 2): the second source is the immediate at bits 32..63, not the register field at 64 that HFMA2's B uses in that form. Pokopia's
    blur 85446a6753300fc8 steps its loop with HADD2 R6, R6, 2.0h; reading R0 there, the loop never ended and the GPU hung"""
    HADD2 = (0x000fe20000000800, 0x4000400006067430)   # HADD2 R6, R6, 2, 2 (field 64 = R0)
    HMUL2 = (HADD2[0], HADD2[1] & ~0xfff | 0x432)      # HMUL2 R6, R6, 2, 2: the same fields (no game encoding met)

    def test_hadd2_adds_the_immediate(self):
        msl = self.kept(self.HADD2, srcs=(6,))
        self.assertIn('spvFAdd', msl)
        self.assertRegex(msl, r'\b2\.0\b')   # read from R0 (never written) it was 0, and the add folded away

    def test_hmul2_multiplies_by_the_immediate(self):
        msl = self.kept(self.HMUL2, srcs=(6,))
        self.assertIn('spvFMul', msl)
        self.assertRegex(msl, r'\b2\.0\b')


class CompareFtz(Alu):
    """FSETP / FSET .FTZ (bit 80): a denormal operand compares as zero, as on NVIDIA; Apple's GPUs keep denormals. Mario Kart World's deferred lighting 635061c90d75a8d1
    normalises its four depth-weighted samples by 1 / sum only where FSETP.NEU.FTZ says sum != 0: a denormal sum passed, its reciprocal overflowed, and the NaN came out
    of a min(x, 1.0) as a fully lit dot. test_dmsh_maxwell_ftz.py has Maxwell's"""
    FSETP = (0x000fca0003f1d000, 0x800000141300720b)   # FSETP.NEU.FTZ.AND P0, PT, R19, -R20, PT (the game's guard, there on R35 and -R10)
    FSET = (0x000fe2000381d000, 0x800000141306720a)    # FSET.NEU.FTZ.AND R6, R19, -R20, PT
    FSEL = (0x000fe40000000000, 0x0000001413067208)    # FSEL R6, R19, R20, P0: keeps the predicate
    FLUSH = '1.1754943508222875'                       # FLT_MIN, the bound under which an operand is flushed

    def test_fsetp_flushes_both_operands(self):
        self.assertEqual(self.kept(self.FSETP, self.FSEL, srcs=(19, 20)).count(self.FLUSH), 2)

    def test_fset_flushes_both_operands(self):
        self.assertEqual(self.kept(self.FSET, srcs=(19, 20)).count(self.FLUSH), 2)

    def test_without_ftz_compares_as_is(self):
        self.assertNotIn(self.FLUSH, self.kept((self.FSETP[0] & ~(1 << 16), self.FSETP[1]), self.FSEL, srcs=(19, 20)))

    def test_against_zero_flushes_one(self):
        self.assertEqual(self.kept((self.FSETP[0], 0x000000ff1300720b), self.FSEL, srcs=(19, 20)).count(self.FLUSH), 1)




def s2r(rd, sr): return (0x000e260000000000 | sr << 8, 0x0000000000007919 | rd << 16)   # S2R Rd, SR (0x21 SR_TID.X, 0x25 SR_CTAID.X)


class F2ip(Alu):
    """F2IP.U8.F32.NTZ Rd, a, b, RZ (0x243): each float rounded to the nearest integer, saturated to a byte and NaN to 0, b in byte 0 and a in byte 1. The Legend of Zelda:
    Ocarina of Time's colour converter 99951da6e5cd38f5 has F2IP R22, R13, R12, RZ at +0x530; here it is on R6, R4, R5"""
    GAME = (0x000fe200000004ff, 0x0000000c0d167243)
    F2IP = (GAME[0], GAME[1] & ~0xffffffff0000 | 6 << 16 | 4 << 24 | 5 << 32)

    def msl(self):   # a (R4) from SR_TID.X, b (R5) from SR_CTAID.X
        return self.kept(s2r(4, 0x21), s2r(5, 0x25), self.F2IP)

    def test_rounds_saturates_and_drops_nan(self):
        msl = self.msl()
        self.assertEqual(len(re.findall(r'\brint\(', msl)), 2, msl)   # ties to even
        self.assertEqual(len(re.findall(r'\bisnan\(', msl)), 2, msl)
        self.assertEqual(len(re.findall(r'\bmin\([^;]*255\.0\)', msl)), 2, msl)

    def test_a_is_the_high_byte(self):
        msl = self.msl()
        defs = dict(re.findall(r'^\s*\w+ (_\d+) = (.*);$', msl, re.M))
        def source(v, seen=()):   # the shader inputs a value is computed from
            return set().union(*(source(u, seen + (v,)) for u in re.findall(r'_\d+', defs.get(v, '')) if u not in seen),
                               set(re.findall(r'gl_\w+', defs.get(v, ''))))
        high, low = re.search(r'(_\d+) << 8;', msl).group(1), re.search(r'= _\d+ \| (_\d+);', msl).group(1)
        self.assertEqual(source(high), {'gl_LocalInvocationID'}, msl)
        self.assertEqual(source(low), {'gl_WorkGroupID'}, msl)

    def test_other_encodings_are_refused(self):
        for hi in (self.F2IP[0] & ~0xffffff00, self.F2IP[0] | 1 << 8, self.F2IP[0] & ~0xff | 7, self.F2IP[0] | 1 << 16):   # bit 74 clear, 72 set (signed), C = R7, 80 set
            with self.subTest(hi=hex(hi)), self.assertRaises(AssertionError):
                self.kept(s2r(4, 0x21), (hi, self.F2IP[1]))


class F2ipTruncate(Alu):
    """F2IP.U8.F32.NTZ.TRUNC Rd, RZ, b, RZ (78..79 = 3, F2I's rounding field): Ocarina of Time's foliage mesh shader 740e2b04db624fb1 has F2IP R5, RZ, R5, RZ at +0x370, a
    colour channel times 255 that it then shifts by 16 into an RGBA8 word; here it is on R6 and R5. The other rounding modes are the same field (no game encoding met)"""
    GAME = (0x000fe4000000c4ff, 0x00000005ff057243)
    F2IP = (GAME[0], GAME[1] & ~0xff0000 | 6 << 16)

    def msl(self, hi=GAME[0]):   # b (R5) from SR_CTAID.X
        return self.kept(s2r(5, 0x25), (hi, self.F2IP[1]))

    def test_truncates_b_into_byte_0(self):
        msl = self.msl()
        self.assertEqual(len(re.findall(r'\btrunc\(', msl)), 1, msl)
        self.assertNotIn('rint(', msl)
        self.assertEqual(len(re.findall(r'\bisnan\(', msl)), 1, msl)
        self.assertEqual(len(re.findall(r'\bmin\([^;]*255\.0\)', msl)), 1, msl)
        self.assertNotRegex(msl, r'<< 8;')   # a = RZ: byte 1 stays zero

    def test_floor_and_ceiling(self):
        for mode, fn in ((1, 'floor'), (2, 'ceil')):
            with self.subTest(mode=mode):
                msl = self.msl(self.GAME[0] & ~(3 << 14) | mode << 14)
                self.assertEqual(len(re.findall(rf'\b{fn}\(', msl)), 1, msl)
                self.assertNotIn('trunc(', msl)


class UimadImmediateC(Alu):
    """UIMAD URd, URa, URb, imm (0x4a4, form 2: the immediate in the C slot): Ocarina of Time's e9213c7fba8ccf93 +0x43c0 UIMAD UR4, UR4, UR6, 0xa, here with UR4 and UR6
    from c[0], moved to R6"""
    UIMAD = (0x000fcc000f8e0206, 0x0000000a040474a4)
    MOV = (0x000fe20000000f00, 0x0000000400067c02)   # MOV R6, UR4

    def test_adds_the_immediate(self):
        msl = self.kept(uldc(4, 0, 0x40), uldc(6, 0, 0x44), self.UIMAD, self.MOV)
        self.assertRegex(msl, r'\* as_type<int>\([^;]*\);\s*int _\d+ = _\d+ \+ 10;')


class PredicateAlias(Alu):
    """Dual predicate outputs must both read their inputs before either destination is written. The second output of an ISETP/FSETP whose first output
    aliases its positive accumulator used the new accumulator instead. These constant cases keep that output through a guarded move and a shared store."""
    CTRL = 0x000fe20000000000 << 64

    @staticmethod
    def words(value): return value >> 64, value & ((1 << 64) - 1)

    def compare(self, comparison, dest0, dest1=7, pred=7, *, bop=0, negate=False, ex=False, uniform=False, floating=False):
        zero = 63 if uniform else 255
        opcode = 0x28c if uniform else 0x20b if floating else 0x20c
        value = (self.CTRL | opcode | (7 << 12) | (zero << 24) | (zero << 32) | (comparison << 76)
                 | (dest0 << 81) | (dest1 << 84) | (pred << 87) | (bop << 74) | (int(negate) << 90))
        if ex: value |= (1 << 72) | (2 << 68)
        return self.words(value)

    def move(self, rd, value, pred=7):
        return self.words(self.CTRL | 0x802 | (pred << 12) | (rd << 16) | (value << 32))

    def check_outputs(self, *, ex=False, uniform=False, floating=False):
        # False AND true and true OR false change the first output's aliased input. XOR also catches a flipped source; negated inputs and non-aliasing outputs are controls.
        for bop, comparison in ((0, False), (1, True), (2, False), (2, True)):
            for negate in (False, True):
                for alias in (False, True):
                    with self.subTest(bop=bop, comparison=comparison, negate=negate, alias=alias):
                        initial = bop != 1
                        accumulator = initial != negate
                        expected = ((not comparison) and accumulator if bop == 0 else
                                    (not comparison) or accumulator if bop == 1 else (not comparison) != accumulator)
                        pre = [self.move(6, 0), self.compare(2 if initial else 5, 0, uniform=uniform)]
                        if ex: pre.append(self.compare(2 if comparison else 5, 2, uniform=uniform))
                        test = self.compare(2 if ex or comparison else 5, 0 if alias else 3, 1, 0,
                                            bop=bop, negate=negate, ex=ex, uniform=uniform, floating=floating)
                        if uniform:
                            # @UP1 UMOV UR4,1; MOV R6,UR4. The zero keeps the other branch defined.
                            used = [(0x000fe20000000000, 0x0000003f00047c82), (0x000fe20000000000, 0x0000000100041882),
                                    (0x000fe20000000f00, 0x0000000400067c02)]
                        else:
                            used = [self.move(6, 1, pred=1)]
                        # The common STORE is guarded by !P0; make it unconditional so only the second predicate determines the result.
                        store = STORE[0], STORE[1] & ~0xf000 | 0x7000
                        code = [s2r_tid(9), *pre, test, *used, store, EXIT]
                        msl = self.translate(b''.join(inst(*waiting(c)) for c in code), shared=0x1000)
                        self.assertIn(f'if ({str(expected).lower()})', msl)

    def test_isetp_reads_both_inputs_before_writing(self): self.check_outputs()

    def test_isetp_ex_reads_both_inputs_before_writing(self): self.check_outputs(ex=True)

    def test_uisetp_reads_both_inputs_before_writing(self): self.check_outputs(uniform=True)

    def test_uisetp_ex_reads_both_inputs_before_writing(self): self.check_outputs(ex=True, uniform=True)

    def test_fsetp_reads_both_inputs_before_writing(self): self.check_outputs(floating=True)


if __name__ == '__main__':
    unittest.main()
