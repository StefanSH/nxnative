"""BAHS descriptors belong to the binary array, not to control sections whose length fields can mimic them. Synthetic bytes only."""
import os
import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'dm/gfx/tools'))
_old = os.environ.get('DM_GAME'); os.environ['DM_GAME'] = '0400486024DEC000'
import shader_split as ss
if _old is None: del os.environ['DM_GAME']
else: os.environ['DM_GAME'] = _old


def control(stage, size=0xe0):
    c = bytearray(size); c[:4] = ss.CTL_MAGIC; c[4:8] = b'\xc9\0\0\0'
    struct.pack_into('<I', c, 0x30, size)
    struct.pack_into('<III', c, 0x38, 0x100, 0, 0x100)
    struct.pack_into('<I', c, 0x44, 0x100); c[0x56] = stage
    return c


def archive(stray=True):
    d = bytearray(0x1300); d[:4] = b'BAHS'; struct.pack_into('<II', d, 0x18, 0x300, 0x1000)
    struct.pack_into('<II', d, 0x20, 8 + 3 * 0x300, 3)
    for i, (kind, stage) in enumerate(((3, 5), (0, 0), (1, 0))):
        record = 0x28 + i * 0x300; entry, ctl = record + 0x10, record + 0x30
        struct.pack_into('<4I', d, record, 0x300, kind, 0, 0)
        struct.pack_into('<IIIi', d, entry, i * 0x100, 0, 0xe0, ctl - entry)
        d[ctl:ctl + 0xe0] = control(stage)
        struct.pack_into('<I', d, 0x1000 + i * 0x100, 0x7919 if not i else 0x481 if i == 1 else 0x1481)
    # Control +0x38 looks like {code offset, 0, control size, control relative offset}; its alleged code points at the vertex SPH.
    if stray: d[0x190:0x290] = control(5, 0x100)
    struct.pack_into('<II', d, 0x928, 8 + 2 * 16, 2)
    struct.pack_into('<4I', d, 0x930, 16, 0, 0, 0)
    struct.pack_into('<4I', d, 0x940, 16, 0, 0, 1)
    return d


class BahsRecords(unittest.TestCase):
    def test_length_fields_inside_a_control_are_not_a_shader(self):
        got = ss.bahs_shaders(archive(), '/synthetic')
        self.assertEqual([(where, stage) for where, stage, _, _ in got],
                         [('/synthetic#BAHS@0x38', 'cs'), ('/synthetic#BAHS@0x338', 'vs'), ('/synthetic#BAHS@0x638', 'ps')])
        expected = ss.bahs_shaders(archive(stray=False), '/synthetic')
        self.assertEqual([ss.skey(c, k) for _, _, c, k in got], [ss.skey(c, k) for _, _, c, k in expected])
        self.assertEqual(ss.BAHS_VAR[got[1][0]], ss.BAHS_VAR[got[2][0]])

    def test_a_missing_program_array_still_bounds_shader_descriptors(self):
        d = archive(); struct.pack_into('<II', d, 0x928, 0, 0)
        self.assertEqual(len(ss.bahs_shaders(d, '/no-programs')), 3)

    def test_an_unknown_binary_array_layout_keeps_existing_scan(self):
        d = archive(stray=False); struct.pack_into('<II', d, 0x20, 0, 0)
        self.assertEqual([stage for _, stage, _, _ in ss.bahs_shaders(d, '/unknown')], ['cs', 'vs', 'ps'])

    def test_a_record_past_the_array_end_keeps_existing_scan(self):
        d = archive(stray=False); struct.pack_into('<I', d, 0x28, 0x10000)
        self.assertEqual(len(ss.bahs_shaders(d, '/bad-array')), 3)

    def test_a_maxwell_control_and_code_header_still_read(self):
        d = bytearray(0x1100); d[:4] = b'BAHS'; struct.pack_into('<II', d, 0x18, 0x100, 0x1000)
        struct.pack_into('<II', d, 0x20, 0xa08, 1); struct.pack_into('<4I', d, 0x28, 0xa00, 3, 0, 0)
        struct.pack_into('<IIIi', d, 0x38, 0, 0, 0x880, 0x20)
        d[0x58:0x5c] = ss.CTL_MAGIC; struct.pack_into('<I', d, 0x58 + 0x20, 0x880); struct.pack_into('<I', d, 0x58 + 0x704, 0x100)
        d[0x1000:0x1004] = ss.CS_MAGIC
        struct.pack_into('<II4I', d, 0xa28, 24, 1, 16, 0, 0, 0)
        got = ss.bahs_shaders(d, '/maxwell')
        self.assertEqual([(where, stage) for where, stage, _, _ in got], [('/maxwell#BAHS@0x38', 'cs')])
        self.assertEqual(got[0][3], ss.CS_MAGIC + bytes(0xfc))


if __name__ == '__main__':
    unittest.main()
