// Crypt of the Caffeinated King
// A tiny terminal dungeon crawler in AArch64 assembly for macOS (Apple Silicon).
//
//     clang -o crypt crypt.s && ./crypt
//
// Text is formatted with vsnprintf and passes through _emit, which expands
// single control bytes (\001..\024, see colortab) into ANSI colour codes, or
// drops them when stdout is not a colour terminal.
//
// Colour tokens:  \001 reset  \002 bold  \003 dim  \004 red  \005 green
//   \006 yellow  \007 gold  \016 blue  \017 magenta  \020 cyan  \021 grey
//   \022 dark  \023 white  \024 brown

// ---------- macros ----------

.macro LA reg, sym                      // reg = &sym
	adrp	\reg, \sym@PAGE
	add	\reg, \reg, \sym@PAGEOFF
.endm

.macro LDQ reg, sym                     // reg = sym
	adrp	\reg, \sym@PAGE
	ldr	\reg, [\reg, \sym@PAGEOFF]
.endm

.macro STQ reg, sym                     // sym = reg   (clobbers x16)
	adrp	x16, \sym@PAGE
	str	\reg, [x16, \sym@PAGEOFF]
.endm

.macro ADDQ sym, val                    // sym += val  (clobbers x16, x17)
	adrp	x16, \sym@PAGE
	ldr	x17, [x16, \sym@PAGEOFF]
	add	x17, x17, \val
	str	x17, [x16, \sym@PAGEOFF]
.endm

.macro STR reg, s                       // reg = address of string literal
	.pushsection __TEXT,__cstring,cstring_literals
L_s\@:	.asciz "\s"
	.popsection
	LA	\reg, L_s\@
.endm

.macro SAY s                            // outf(s, x1..x7)
	STR	x0, "\s"
	bl	_outf
.endm

.macro MSG s                            // msgbuf = sfmt(s, x2..x7)
	LA	x0, msgbuf
	STR	x1, "\s"
	bl	_sfmt
.endm

.macro LOG s                            // append sfmt(s, x2..x7) to the combat log
	bl	_logslot
	STR	x1, "\s"
	bl	_sfmt
.endm

.macro ENTER
	stp	x29, x30, [sp, -96]!
	mov	x29, sp
	stp	x19, x20, [sp, 16]
	stp	x21, x22, [sp, 32]
	stp	x23, x24, [sp, 48]
	stp	x25, x26, [sp, 64]
	stp	x27, x28, [sp, 80]
.endm

.macro LEAVE
	ldp	x19, x20, [sp, 16]
	ldp	x21, x22, [sp, 32]
	ldp	x23, x24, [sp, 48]
	ldp	x25, x26, [sp, 64]
	ldp	x27, x28, [sp, 80]
	ldp	x29, x30, [sp], 96
	ret
.endm

.macro STDOUT reg
	adrp	\reg, ___stdoutp@GOTPAGE
	ldr	\reg, [\reg, ___stdoutp@GOTPAGEOFF]
	ldr	\reg, [\reg]
.endm

.macro STDIN reg
	adrp	\reg, ___stdinp@GOTPAGE
	ldr	\reg, [\reg, ___stdinp@GOTPAGEOFF]
	ldr	\reg, [\reg]
.endm

	.text
	.p2align 2

// ---------- output ----------

// outf(x0 fmt, x1..x7 args): format and print.
_outf:
	stp	x29, x30, [sp, -80]!
	mov	x29, sp
	stp	x1, x2, [sp, 16]
	stp	x3, x4, [sp, 32]
	stp	x5, x6, [sp, 48]
	str	x7, [sp, 64]
	mov	x2, x0
	add	x3, sp, 16                      // va_list on Darwin is a plain pointer
	LA	x0, fmtbuf
	mov	x1, 4096
	bl	_vsnprintf
	LA	x0, fmtbuf
	bl	_emit
	ldp	x29, x30, [sp], 80
	ret

// sfmt(x0 dst, x1 fmt, x2..x7 args) -> x0 length. dst holds 256 bytes.
_sfmt:
	stp	x29, x30, [sp, -64]!
	mov	x29, sp
	stp	x2, x3, [sp, 16]
	stp	x4, x5, [sp, 32]
	stp	x6, x7, [sp, 48]
	mov	x2, x1
	add	x3, sp, 16
	mov	x1, 256
	bl	_vsnprintf
	sxtw	x0, w0
	ldp	x29, x30, [sp], 64
	ret

// emit(x0 str): expand colour tokens and write to stdout.
_emit:
	stp	x29, x30, [sp, -16]!
	mov	x29, sp
	LA	x1, outbuf
	mov	x3, x1
	LDQ	x9, use_color
	LA	x10, colortab
1:	ldrb	w2, [x0], 1
	cbz	w2, 3f
	cmp	w2, 21
	b.hs	2f
	ldr	x11, [x10, x2, lsl 3]
	cbz	x11, 2f
	cbz	x9, 1b
4:	ldrb	w12, [x11], 1
	cbz	w12, 1b
	strb	w12, [x1], 1
	b	4b
2:	strb	w2, [x1], 1
	b	1b
3:	sub	x2, x1, x3
	mov	x0, x3
	mov	x1, 1
	STDOUT	x3
	bl	_fwrite
	ldp	x29, x30, [sp], 16
	ret

_flush:
	stp	x29, x30, [sp, -16]!
	mov	x29, sp
	STDOUT	x0
	bl	_fflush
	ldp	x29, x30, [sp], 16
	ret

// slow(x0 fmt, x1..x7 args): print one character at a time, 10 ms apart.
_slow:
	stp	x29, x30, [sp, -96]!
	mov	x29, sp
	stp	x19, x20, [sp, 80]
	stp	x1, x2, [sp, 16]
	stp	x3, x4, [sp, 32]
	stp	x5, x6, [sp, 48]
	str	x7, [sp, 64]
	mov	x2, x0
	add	x3, sp, 16
	LA	x0, slowbuf
	mov	x1, 1024
	bl	_vsnprintf
	LA	x19, slowbuf
	LDQ	x8, use_color
	cbnz	x8, 1f
	mov	x0, x19                         // plain transcripts print at full speed
	bl	_emit
	b	3f
1:	ldrb	w20, [x19], 1
	cbz	w20, 3f
	and	w8, w20, 0xC0
	cmp	w8, 0x80                        // UTF-8 continuation byte: no pause
	b.eq	2f
	cmp	w20, 32                         // colour token or newline: no pause
	b.lo	2f
	mov	w0, 10000
	bl	_usleep
2:	strb	w20, [sp, 72]
	strb	wzr, [sp, 73]
	add	x0, sp, 72
	bl	_emit
	bl	_flush
	b	1b
3:	ldp	x19, x20, [sp, 80]
	ldp	x29, x30, [sp], 96
	ret

// rep(x0 str, x1 n): print str n times (n <= 0 prints nothing).
_rep:
	ENTER
	mov	x19, x0
	mov	x20, x1
1:	cmp	x20, 0
	b.le	2f
	mov	x0, x19
	bl	_outf
	sub	x20, x20, 1
	b	1b
2:	LEAVE

_clear:
	ENTER
	LDQ	x8, use_color
	cbz	x8, 1f
	SAY	"\033[H\033[2J\033[3J"
	bl	_flush
	LEAVE
1:	LEAVE

_divider:
	ENTER
	SAY	"\022"
	STR	x0, "─"
	mov	x1, 52
	bl	_rep
	SAY	"\001\n"
	LEAVE

// hp_bar(x0 cur, x1 max, x2 width)
_hp_bar:
	ENTER
	mov	x19, x0
	mov	x20, x1
	mov	x21, x2
	mov	x22, 0                          // filled
	cmp	x19, 0
	b.le	1f
	mul	x8, x19, x21                    // round(cur * width / max), ties to even
	udiv	x9, x8, x20
	msub	x10, x9, x20, x8
	lsl	x10, x10, 1
	cmp	x10, x20
	b.lo	2f
	b.hi	3f
	tbz	x9, 0, 2f
3:	add	x9, x9, 1
2:	cmp	x9, x21
	csel	x22, x9, x21, ls
1:	mov	x8, 100
	mul	x8, x19, x8
	mov	x9, 66
	mul	x9, x20, x9
	mov	x1, 5                           // green above 66%
	cmp	x8, x9
	b.gt	4f
	mov	x9, 33
	mul	x9, x20, x9
	mov	x1, 6                           // yellow above 33%
	cmp	x8, x9
	b.gt	4f
	mov	x1, 4                           // red
4:	SAY	"%c"
	STR	x0, "█"
	mov	x1, x22
	bl	_rep
	SAY	"\022"
	STR	x0, "░"
	sub	x1, x21, x22
	bl	_rep
	SAY	"\001"
	LEAVE

// ---------- input ----------

// readline(x0 prompt, x1 lowercase?) -> x0 trimmed line. EOF quits the game.
_readline:
	ENTER
	mov	x19, x1
	bl	_outf
	bl	_flush
	LA	x0, inbuf
	mov	w1, 512
	STDIN	x2
	bl	_fgets
	cbz	x0, _rain_exit
	LA	x0, inbuf
	mov	w1, 10
	bl	_strchr
	cbnz	x0, 2f
1:	STDIN	x0                              // discard the rest of an overlong line
	bl	_fgetc
	cmn	w0, 1
	b.eq	2f
	cmp	w0, 10
	b.ne	1b
2:	LA	x20, inbuf
3:	ldrb	w8, [x20]
	cbz	w8, 4f
	cmp	w8, 32
	b.hi	4f
	add	x20, x20, 1
	b	3b
4:	mov	x0, x20
	bl	_strlen
5:	cbz	x0, 6f
	sub	x9, x0, 1
	ldrb	w8, [x20, x9]
	cmp	w8, 32
	b.hi	6f
	strb	wzr, [x20, x9]
	mov	x0, x9
	b	5b
6:	cbz	x19, 8f
	mov	x9, x20
7:	ldrb	w8, [x9]
	cbz	w8, 8f
	sub	w10, w8, 'A'
	cmp	w10, 25
	b.hi	71f
	add	w8, w8, 32
	strb	w8, [x9]
71:	add	x9, x9, 1
	b	7b
8:	mov	x0, x20
	LEAVE

_on_int:
_rain_exit:
	ENTER
	SAY	"\003\n  You step out of the crypt. The wind smells like rain.\001\n"
	mov	x0, 0
	bl	_exit

// ---------- random ----------

// SplitMix64 with rejection sampling. Keep fixed-width operations so a seed
// can be passed between players and produce the same run.
_rnd:
	neg	w8, w0
	udiv	w9, w8, w0
	msub	w8, w9, w0, w8                  // 2^32 mod n
	LDQ	x10, rng_step
	LDQ	x11, rng_mix1
	LDQ	x12, rng_mix2
	LDQ	x13, rng_state
1:	add	x13, x13, x10
	eor	x9, x13, x13, lsr 30
	mul	x9, x9, x11
	eor	x9, x9, x9, lsr 27
	mul	x9, x9, x12
	eor	x9, x9, x9, lsr 31
	cmp	w9, w8
	b.lo	1b
	STQ	x13, rng_state
	udiv	w10, w9, w0
	msub	w0, w10, w0, w9
	ret

// The floor plan depends only on the run seed and floor number. Throwing
// extra dice on the dock cannot rearrange the boilerworks downstairs.
_deal_floor:
	ENTER
	LDQ	x19, rng_state
	LDQ	x8, run_seed
	LDQ	x9, depth
	orr	x8, x8, x9, lsl 32
	STQ	x8, rng_state
	bl	_gen_dungeon
	STQ	x19, rng_state
	LEAVE

// randint(x0 lo, x1 hi) -> uniform in [lo, hi]
_randint:
	ENTER
	mov	x19, x0
	sub	x0, x1, x0
	add	x0, x0, 1
	bl	_rnd
	add	x0, x0, x19
	LEAVE

// ---------- player ----------

// hurt(x0 dmg) -> damage taken after armor (at least 1)
_hurt:
	LDQ	x1, p_arm
	sub	x0, x0, x1
	cmp	x0, 1
	csinc	x0, x0, xzr, ge
	adrp	x16, p_hp@PAGE
	ldr	x17, [x16, p_hp@PAGEOFF]
	sub	x17, x17, x0
	str	x17, [x16, p_hp@PAGEOFF]
	ret

// heal(x0 amt) -> HP actually gained
_heal:
	LDQ	x1, p_hp
	LDQ	x2, p_max
	add	x3, x1, x0
	cmp	x3, x2
	csel	x3, x3, x2, le
	STQ	x3, p_hp
	sub	x0, x3, x1
	ret

// Caller has checked stock. Return the amount actually healed.
_drink_potion:
	ADDQ	p_pot, -1
	LDQ	x8, p_class
	cmp	x8, 1
	mov	x0, 10
	mov	x9, 15
	csel	x0, x9, x0, eq
	b	_heal

// ---------- procgen ----------

// article(x0 word) -> "an" before a vowel, else "a"
_article:
	ldrb	w8, [x0]
	orr	w8, w8, 0x20
	cmp	w8, 'a'
	b.eq	1f
	cmp	w8, 'e'
	b.eq	1f
	cmp	w8, 'i'
	b.eq	1f
	cmp	w8, 'o'
	b.eq	1f
	cmp	w8, 'u'
	b.eq	1f
	adrp	x0, L_a@PAGE
	add	x0, x0, L_a@PAGEOFF
	ret
1:	adrp	x0, L_an@PAGE
	add	x0, x0, L_an@PAGEOFF
	ret

// Fills m_*: a base monster, sometimes with a prefix and/or suffix.
_procgen_monster:
	ENTER
	mov	x0, 11
	bl	_rnd
	LA	x19, monsters
	mov	x8, 64
	madd	x19, x0, x8, x19
	ldr	x20, [x19, 16]                  // hp
	ldr	x21, [x19, 24]                  // atk
	ldr	x22, [x19, 32]                  // gold
	ldr	x27, [x19]                      // article
	STR	x23, ""                         // prefix
	mov	x24, x23                        // space after prefix
	mov	x25, x23                        // suffix
	mov	x26, x23                        // space before suffix
	mov	x0, 100
	bl	_rnd
	mov	x28, x0
	cmp	x28, 65                         // 35%: plain
	b.hs	5f
	cmp	x28, 30                         // 30%: prefix only
	b.lo	1f
	mov	x0, 10                          // 25% suffix only, 10% both
	bl	_rnd
	LA	x8, suffixes
	add	x8, x8, x0, lsl 5
	ldr	x25, [x8]
	STR	x26, " "
	ldr	x9, [x8, 8]
	add	x20, x20, x9
	ldr	x9, [x8, 16]
	add	x21, x21, x9
	ldr	x9, [x8, 24]
	add	x22, x22, x9
	cmp	x28, 55
	b.lo	5f
1:	mov	x0, 11
	bl	_rnd
	LA	x8, prefixes
	add	x8, x8, x0, lsl 5
	ldr	x23, [x8]
	STR	x24, " "
	ldr	x9, [x8, 8]
	add	x20, x20, x9
	ldr	x9, [x8, 16]
	add	x21, x21, x9
	ldr	x9, [x8, 24]
	add	x22, x22, x9
	ldrb	w9, [x27]
	cmp	w9, 't'                         // "the" stays "the"
	b.eq	5f
	mov	x0, x23
	bl	_article
	mov	x27, x0
5:	LDQ	x8, depth                       // deeper floors: +4 hp, +1 atk, +5 gold each
	sub	x8, x8, 1
	add	x20, x20, x8, lsl 2
	add	x21, x21, x8
	mov	x9, 5
	madd	x22, x8, x9, x22
	cmp	x20, 1
	csinc	x20, x20, xzr, ge
	cmp	x21, 1
	csinc	x21, x21, xzr, ge
	cmp	x22, 1
	csinc	x22, x22, xzr, ge
	STQ	x20, m_hp
	STQ	x21, m_atk
	STQ	x22, m_gold
	ldr	x8, [x19, 40]
	STQ	x8, m_flavor
	ldr	x8, [x19, 48]
	STQ	x8, m_art
	ldr	x8, [x19, 56]
	STQ	x8, m_trait
	LA	x0, m_name
	STR	x1, "%s %s%s%s%s%s"
	mov	x2, x27
	mov	x3, x23
	mov	x4, x24
	ldr	x5, [x19, 8]
	mov	x6, x26
	mov	x7, x25
	bl	_sfmt
	LEAVE

// Fills t_name, t_kind (0 gold, 1 potion, 2 weapon, 3 armor, 4 beans), t_lo, t_hi.
_procgen_treasure:
	ENTER
	mov	x0, 100
	bl	_rnd
	cmp	x0, 15
	b.hs	1f
	mov	x0, 5                           // 15%: a hand-crafted special
	bl	_rnd
	LA	x8, specials
	add	x19, x8, x0, lsl 5
	LA	x0, t_name
	ldr	x1, [x19]
	mov	x2, 256
	bl	_strlcpy
	ldr	x8, [x19, 8]
	STQ	x8, t_kind
	ldr	x8, [x19, 16]
	STQ	x8, t_lo
	ldr	x8, [x19, 24]
	STQ	x8, t_hi
	LEAVE
1:	mov	x0, 100
	bl	_rnd
	mov	x19, x0
	cmp	x19, 30
	b.hs	2f
	mov	x0, 2                           // gold
	bl	_rnd
	cbnz	x0, 11f
	STR	x1, "a small pouch of gold"
	mov	x20, 8
	mov	x21, 18
	b	12f
11:	STR	x1, "a forgotten gem"
	mov	x20, 15
	mov	x21, 30
12:	LA	x0, t_name
	mov	x2, 256
	bl	_strlcpy
	STQ	xzr, t_kind
	STQ	x20, t_lo
	STQ	x21, t_hi
	LEAVE
2:	cmp	x19, 75
	b.hs	4f
	mov	x0, 11                          // weapon or armor
	bl	_rnd
	LA	x8, materials
	add	x8, x8, x0, lsl 4
	ldr	x20, [x8]                       // material
	ldr	x21, [x8, 8]                    // bonus
	cmp	x19, 55
	b.hs	21f
	mov	x0, 8
	bl	_rnd
	LA	x8, weapon_types
	ldr	x22, [x8, x0, lsl 3]
	mov	x23, 2
	b	22f
21:	mov	x0, 6
	bl	_rnd
	LA	x8, armor_types
	ldr	x22, [x8, x0, lsl 3]
	mov	x23, 3
22:	STR	x24, ""
	mov	x25, x24
	mov	x0, 100
	bl	_rnd
	cmp	x0, 40
	b.hs	23f
	mov	x0, 13
	bl	_rnd
	LA	x8, themes
	ldr	x25, [x8, x0, lsl 3]
	STR	x24, " "
	add	x21, x21, 1
23:	mov	x0, x20
	bl	_article
	mov	x2, x0
	LA	x0, t_name
	STR	x1, "%s %s %s%s%s"
	mov	x3, x20
	mov	x4, x22
	mov	x5, x24
	mov	x6, x25
	bl	_sfmt
	STQ	x23, t_kind
	STQ	x21, t_lo
	LEAVE
4:	cmp	x19, 88
	b.hs	5f
	mov	x0, 12                          // potion
	bl	_rnd
	LA	x8, potion_adj
	ldr	x20, [x8, x0, lsl 3]
	mov	x0, x20
	bl	_article
	mov	x2, x0
	LA	x0, t_name
	STR	x1, "%s %s potion"
	mov	x3, x20
	bl	_sfmt
	mov	x8, 1
	STQ	x8, t_kind
	LEAVE
5:	LA	x0, t_name                      // coffee beans
	STR	x1, "a twist of paper full of coffee beans"
	mov	x2, 256
	bl	_strlcpy
	mov	x8, 4
	STQ	x8, t_kind
	mov	x8, 2
	STQ	x8, t_lo
	LEAVE

// ---------- panels ----------

_show_art:
	ENTER
	mov	x1, x0
	SAY	"%s"
	LEAVE

// Draw the local view at the landing and in quiet rooms.
_floor_scene:
	LDQ	x8, depth
	sub	x8, x8, 1
	LA	x9, floor_scenes
	add	x9, x9, x8, lsl 4
	ldp	x0, x1, [x9]
	b	_render_top

// map_glyph(x0 x, x1 y) -> coloured glyph. A visited doorway scouts its
// four neighbours. A quiet doorway can still be trapped.
_map_glyph:
	LDQ	x8, p_x
	LDQ	x9, p_y
	cmp	x0, x8
	b.ne	1f
	cmp	x1, x9
	b.ne	1f
	STR	x0, "\002\005@\001"
	ret
1:	mov	x8, 5
	madd	x9, x1, x8, x0
	cmp	x9, 24
	b.ne	2f
	STR	x0, "\002\007>\001"
	ret
2:	LA	x8, rooms
	ldrb	w10, [x8, x9]
	cmp	w10, 10                         // the crew's signal travels across the floor
	b.ne	3f
	STR	x0, "\002\020!\001"
	ret
3:	LA	x8, visited
	add	x8, x8, x9
	ldrb	w11, [x8]
	cbz	w11, 4f
	cbnz	w10, 9f
	STR	x0, "\021·\001"
	ret
4:	cbz	x0, 5f                          // west
	ldurb	w11, [x8, -1]
	cbnz	w11, 9f
5:	cmp	x0, 4                           // east
	b.eq	6f
	ldrb	w11, [x8, 1]
	cbnz	w11, 9f
6:	cbz	x1, 7f                          // south
	ldurb	w11, [x8, -5]
	cbnz	w11, 9f
7:	cmp	x1, 4                           // north
	b.eq	8f
	ldrb	w11, [x8, 5]
	cbnz	w11, 9f
8:	STR	x0, "\022?\001"
	ret
9:	LA	x8, room_glyphs
	ldr	x0, [x8, x10, lsl 3]
	ret

_map:
	ENTER
	SAY	"\022╭"
	STR	x0, "─"
	mov	x1, 16
	bl	_rep
	SAY	"╮\001\n"
	mov	x20, 4
1:	SAY	"\022│\001 "
	mov	x19, 0
2:	SAY	" "
	mov	x0, x19
	mov	x1, x20
	bl	_map_glyph
	bl	_outf
	SAY	" "
	add	x19, x19, 1
	cmp	x19, 5
	b.lo	2b
	LA	x8, map_key
	ldr	x1, [x8, x20, lsl 3]
	SAY	"\022│\001  %s\n"
	subs	x20, x20, 1
	b.ge	1b
	SAY	"\022╰"
	STR	x0, "─"
	mov	x1, 16
	bl	_rep
	SAY	"╯\001\n"
	LEAVE

_status:
	ENTER
	LA	x8, p_name                      // name length in code points
	mov	x19, 0
1:	ldrb	w9, [x8], 1
	cbz	w9, 2f
	and	w10, w9, 0xC0
	cmp	w10, 0x80
	cinc	x19, x19, ne
	b	1b
2:	LDQ	x8, p_class
	LA	x9, class_names
	ldr	x20, [x9, x8, lsl 3]
	mov	x0, x20
	bl	_strlen
	mov	x8, 42
	sub	x19, x8, x19
	sub	x19, x19, x0
	LA	x1, p_name
	mov	x2, x20
	SAY	"\022╭─ %s the %s "
	STR	x0, "─"
	mov	x1, x19
	bl	_rep
	SAY	"╮\001\n"
	LA	x0, tmpa
	STR	x1, "%ld/%ld"
	LDQ	x2, p_hp
	LDQ	x3, p_max
	bl	_sfmt
	SAY	"│ HP  "
	LDQ	x0, p_hp
	LDQ	x1, p_max
	mov	x2, 18
	bl	_hp_bar
	LA	x0, tmpb
	STR	x1, "  \023%-7s\001\021Turn %ld\001"
	LA	x2, tmpa
	LDQ	x3, p_turns
	bl	_sfmt
	LA	x0, tmpb
	bl	_vislen
	mov	x8, 27
	sub	x19, x8, x0
	LA	x1, tmpb
	SAY	"%s"
	STR	x0, " "
	mov	x1, x19
	bl	_rep
	SAY	"│\n"
	LDQ	x1, p_atk
	LDQ	x2, p_arm
	LDQ	x3, p_gold
	LDQ	x4, p_pot
	LDQ	x5, p_beans
	STR	x0, " \023ATK\001 %-3ld \023ARM\001 %-3ld \007Gold\001 %-5ld \017Potions\001 %-3ld \024Beans\001 %ld"
	bl	_pline
	LDQ	x1, p_lvl
	LDQ	x2, p_xp
	mov	x8, 20
	mul	x3, x1, x8
	LDQ	x4, depth
	LDQ	x8, crew_mask
	and	x5, x8, 1
	ubfx	x9, x8, 1, 1
	add	x5, x5, x9
	add	x5, x5, x8, lsr 2
	STR	x0, " \023Lv\001  %-3ld \023XP\001 %ld/%ld   \020Floor\001 %ld/3   \020Crew\001 %ld/3"
	bl	_pline
	SAY	"\022╰"
	STR	x0, "─"
	mov	x1, 50
	bl	_rep
	SAY	"╯\001\n"
	LEAVE

// vislen(x0 str) -> printed width: code points, colour tokens excluded
_vislen:
	mov	x1, 0
1:	ldrb	w2, [x0], 1
	cbz	w2, 2f
	cmp	w2, 32
	b.lo	1b
	and	w3, w2, 0xC0
	cmp	w3, 0x80
	cinc	x1, x1, ne
	b	1b
2:	mov	x0, x1
	ret

// pline(x0 fmt, x1..x6 args): one status-panel row, padded to the border.
_pline:
	ENTER
	mov	x7, x6
	mov	x6, x5
	mov	x5, x4
	mov	x4, x3
	mov	x3, x2
	mov	x2, x1
	mov	x1, x0
	LA	x0, tmpc
	bl	_sfmt
	LA	x0, tmpc
	bl	_vislen
	mov	x8, 50
	sub	x19, x8, x0
	LA	x1, tmpc
	SAY	"│%s"
	STR	x0, " "
	mov	x1, x19
	bl	_rep
	SAY	"│\n"
	LEAVE

// render_top(x0 art, x1 label): clear, art, room label.
_render_top:
	ENTER
	mov	x19, x0
	mov	x20, x1
	bl	_clear
	mov	x0, x19
	bl	_show_art
	SAY	"\n"
	mov	x1, x20
	SAY	"%s"
	bl	_divider
	LEAVE

// render_bottom: map and status panel.
_render_bottom:
	ENTER
	SAY	"\n"
	bl	_map
	SAY	"\n"
	bl	_status
	LEAVE

// ---------- combat ----------

// logslot -> x0 next combat-log line (keeps the last 4).
_logslot:                               // preserves x2..x7 for the caller's sfmt
	ENTER
	mov	x21, x2
	mov	x22, x3
	mov	x23, x4
	mov	x24, x5
	mov	x25, x6
	mov	x26, x7
	LA	x19, logbuf
	LDQ	x20, log_n
	cmp	x20, 4
	b.lo	1f
	mov	x0, x19
	add	x1, x19, 256
	mov	x2, 768
	bl	_memmove
	mov	x20, 3
1:	add	x8, x20, 1
	STQ	x8, log_n
	add	x0, x19, x20, lsl 8
	mov	x2, x21
	mov	x3, x22
	mov	x4, x23
	mov	x5, x24
	mov	x6, x25
	mov	x7, x26
	LEAVE

_render_combat:
	ENTER
	bl	_clear
	LDQ	x0, m_art
	bl	_show_art
	SAY	"\n"
	LA	x0, upbuf
	LA	x1, m_name
	mov	x2, 256
	bl	_strlcpy
	LA	x8, upbuf
1:	ldrb	w9, [x8]
	cbz	w9, 3f
	sub	w10, w9, 'a'
	cmp	w10, 25
	b.hi	2f
	sub	w9, w9, 32
	strb	w9, [x8]
2:	add	x8, x8, 1
	b	1b
3:	LA	x1, upbuf
	SAY	"\002\004  ⚔  %s\001\n"
	LDQ	x8, m_trait
	cbz	x8, 7f
	LA	x9, trait_names
	ldr	x1, [x9, x8, lsl 3]
	SAY	"\003  %s\001\n"
7:	bl	_divider
	SAY	"  \023You\001    "
	LDQ	x0, p_hp
	LDQ	x1, p_max
	mov	x2, 14
	bl	_hp_bar
	LDQ	x1, p_hp
	LDQ	x2, p_max
	SAY	"  \023%ld/%ld\001"
	LDQ	x1, p_pot
	LDQ	x2, p_beans
	SAY	"   \003Potions %ld · Beans %ld\001"
	LDQ	x1, c_buff
	cbz	x1, 8f
	SAY	"  \024%+ld ATK\001"
8:	LDQ	x1, p_poison
	cbz	x1, 9f
	SAY	"  \004Venom -2/turn (%ld)\001"
9:	SAY	"\n"
	SAY	"  \004Foe\001    "
	LDQ	x0, foe_hp
	LDQ	x1, m_hp
	mov	x2, 14
	bl	_hp_bar
	LDQ	x1, foe_hp
	LDQ	x2, m_hp
	SAY	"  \023%ld/%ld\001\n"
	LDQ	x1, c_incoming
	LDQ	x8, c_windup
	cbnz	x8, L_render_windup
	add	x2, x1, 1
	lsr	x2, x2, 1
	SAY	"\020  Quick strike\001   %ld damage (%ld through guard).\n"
	b	L_render_opening
L_render_windup:
	LDQ	x8, boss
	cbz	x8, L_render_foe_tell
	SAY	"\007  Espresso!\001      The King lifts the cup with both hands.\n"
	b	L_render_parry_hint
L_render_foe_tell:
	LDQ	x8, m_trait
	LA	x9, windup_tells
	ldr	x1, [x9, x8, lsl 3]
	SAY	"\007  Wind-up!\001      %s\n"
L_render_parry_hint:
	LDQ	x1, c_incoming
	SAY	"                 %ld damage. [g] parries and opens a riposte.\n"
L_render_opening:
	LDQ	x8, c_opening
	cbz	x8, L_render_history
	SAY	"\005  Opening!\001       [h] riposte now. Double damage, guaranteed hit.\n"
L_render_history:
	SAY	"\n"
	LA	x19, logbuf
	LDQ	x20, log_n
	mov	x21, 0
4:	cmp	x21, x20
	b.hs	5f
	add	x1, x19, x21, lsl 8
	SAY	"%s\n"
	add	x21, x21, 1
	b	4b
5:	cbz	x20, 6f
	SAY	"\n"
6:	LEAVE

// Roll once per enemy action. Invalid input leaves the displayed hit intact.
_prepare_intent:
	ENTER
	LDQ	x19, m_atk
	LDQ	x8, c_quick_left
	cbz	x8, 1f
	sub	x8, x8, 1
	STQ	xzr, c_windup
	b	3f
1:	mov	x8, 1
	STQ	x8, c_windup
	LDQ	x8, boss
	cbz	x8, 2f
	add	x19, x19, 4                     // the King's third turn
	mov	x8, 2
	b	3f
2:	add	x19, x19, 2
	mov	x0, 3
	bl	_rnd
	add	x8, x0, 1                       // one to three quick strikes before the next tell
3:	STQ	x8, c_quick_left
	sub	x0, x19, 1
	add	x1, x19, 1
	bl	_randint
	LDQ	x8, p_arm
	sub	x0, x0, x8
	cmp	x0, 1
	csinc	x0, x0, xzr, ge
	STQ	x0, c_incoming                  // HP loss after armor, before guard
	LEAVE

// Show the final blow on the result screen after its predecessor is cleared.
_combat_recap:
	ENTER
	LDQ	x8, log_n
	cbz	x8, 1f
	sub	x8, x8, 1
	LA	x9, logbuf
	add	x1, x9, x8, lsl 8
	SAY	"%s\n"
1:
	LEAVE

// boss_check: below half HP the King heals once.
_boss_check:
	ENTER
	LDQ	x8, boss
	cbz	x8, 1f
	LDQ	x8, boss_healed
	cbnz	x8, 1f
	LDQ	x8, foe_hp
	LDQ	x9, m_hp
	lsl	x10, x8, 1
	cmp	x10, x9
	b.gt	1f
	add	x8, x8, 15
	cmp	x8, x9
	csel	x8, x8, x9, le
	STQ	x8, foe_hp
	mov	x8, 1
	STQ	x8, boss_healed
	LOG	"\017  The King gulps a triple ristretto. +15 HP.\001"
1:	LEAVE

_setup_boss:
	ENTER
	LA	x0, m_name
	STR	x1, "the Caffeinated King"
	mov	x2, 256
	bl	_strlcpy
	mov	x8, 80
	STQ	x8, m_hp
	mov	x8, 8
	STQ	x8, m_atk
	mov	x8, 100
	STQ	x8, m_gold
	STR	x8, "He sips. He smiles. He sets the cup down very carefully."
	STQ	x8, m_flavor
	LA	x8, art_king
	STQ	x8, m_art
	mov	x8, 1
	STQ	x8, boss
	STQ	xzr, boss_healed
	STQ	xzr, m_trait
	LEAVE

// gain_xp(x0 amount) -> levels gained. Level n needs n*20 XP.
_gain_xp:
	ENTER
	ADDQ	p_xp, x0
	mov	x19, 0
1:	LDQ	x8, p_xp
	LDQ	x9, p_lvl
	mov	x10, 20
	mul	x10, x9, x10
	cmp	x8, x10
	b.lt	2f
	sub	x8, x8, x10
	STQ	x8, p_xp
	ADDQ	p_lvl, 1
	ADDQ	p_max, 4
	ADDQ	p_hp, 4
	ADDQ	p_atk, 1
	add	x19, x19, 1
	b	1b
2:	mov	x0, x19
	LEAVE

// roll_dmg -> a normal hit's damage, including chewed beans
_roll_dmg:
	ENTER
	LDQ	x8, p_atk
	LDQ	x9, c_buff
	add	x8, x8, x9
	sub	x0, x8, 1
	add	x1, x8, 2
	bl	_randint
	cmp	x0, 1
	csinc	x0, x0, xzr, ge
	LEAVE

// apply_hit(x0 dmg, x1 sure hit?) -> damage after the foe's trait (0 = dodged).
_apply_hit:
	ENTER
	mov	x19, x0
	LDQ	x8, m_trait
	cmp	x8, 2                           // evasive: 25% dodge
	b.ne	1f
	cbnz	x1, 2f                          // a riposte catches even an evasive foe
	mov	x0, 100
	bl	_rnd
	cmp	x0, 25
	b.hs	2f
	LA	x2, m_name
	LOG	"\003  %s flickers aside. Miss.\001"
	mov	x0, 0
	LEAVE
1:	cmp	x8, 3                           // armored: -2, at least 1
	b.ne	2f
	sub	x19, x19, 2
	cmp	x19, 1
	csinc	x19, x19, xzr, ge
2:	LDQ	x8, foe_hp
	sub	x8, x8, x19
	STQ	x8, foe_hp
	mov	x0, x19
	LEAVE

// foe_turn(x0 hit message fmt, or 0 for guard). An opening lasts one action.
_foe_turn:
	ENTER
	mov	x19, x0
	STQ	xzr, c_opening
	bl	_boss_check
	LDQ	x8, m_trait
	cmp	x8, 5                           // regenerating
	b.ne	1f
	LDQ	x8, foe_hp
	LDQ	x9, m_hp
	cmp	x8, x9
	b.ge	1f
	add	x8, x8, 2
	cmp	x8, x9
	csel	x8, x8, x9, le
	LDQ	x10, foe_hp
	sub	x3, x8, x10
	STQ	x8, foe_hp
	LA	x2, m_name
	LOG	"\005  %s knits back together. +%ld HP.\001"
1:	LDQ	x20, c_incoming
	cbnz	x19, L_land_hit
	LDQ	x8, c_windup
	cbz	x8, L_guard_quick
	mov	x8, 1
	STQ	x8, c_opening
	LOG	"\005  Parried clean. Your foe is wide open.\001"
	b	4f                              // no contact, so no on-hit trait
L_guard_quick:
	add	x20, x20, 1
	lsr	x20, x20, 1
	STR	x19, "\020  You brace against %s. %ld damage gets through.\001"
L_land_hit:
	LDQ	x8, p_hp
	sub	x8, x8, x20
	STQ	x8, p_hp
	bl	_logslot
	mov	x1, x19
	LA	x2, m_name
	mov	x3, x20
	bl	_sfmt
	LDQ	x8, p_hp
	cmp	x8, 0
	b.le	5f                              // leave the lethal hit visible
	LDQ	x8, m_trait
	cmp	x8, 1                           // venomous: 30% poison for 3 turns
	b.ne	2f
	mov	x0, 100
	bl	_rnd
	cmp	x0, 30
	b.hs	4f
	mov	x8, 3
	STQ	x8, p_poison
	LOG	"\004  Venom seeps into the wound.\001"
	b	4f
2:	cmp	x8, 4                           // light-fingered: 30% steal up to 5 gold
	b.ne	3f
	LDQ	x9, p_gold
	cbz	x9, 4f
	mov	x0, 100
	bl	_rnd
	cmp	x0, 30
	b.hs	4f
	LDQ	x9, p_gold
	mov	x10, 5
	cmp	x9, x10
	csel	x21, x9, x10, lt
	sub	x9, x9, x21
	STQ	x9, p_gold
	ADDQ	m_gold, x21
	mov	x2, x21
	LOG	"\007  It pockets %ld of your gold.\001"
	b	4f
3:	cmp	x8, 6                           // managerial: 35% write-up, -1 ATK this fight
	b.ne	4f
	mov	x0, 100
	bl	_rnd
	cmp	x0, 35
	b.hs	4f
	ADDQ	c_buff, -1
	mov	x0, 4
	bl	_rnd
	LA	x8, writeups
	ldr	x2, [x8, x0, lsl 3]
	LOG	"\004  %s You've been written up. ATK -1 this fight.\001"
4:	LDQ	x8, p_poison
	cbz	x8, 5f
	sub	x8, x8, 1
	STQ	x8, p_poison
	ADDQ	p_hp, -2
	LOG	"\004  Venom burns. -2 HP.\001"
5:	LDQ	x8, p_hp
	cmp	x8, 0
	b.le	6f
	bl	_prepare_intent
6:	LEAVE

// combat -> x0: 0 won, 1 fled, 2 dead
_combat:
	ENTER
	LDQ	x8, m_hp
	STQ	x8, foe_hp
	STQ	xzr, log_n
	STQ	xzr, c_buff
	STQ	xzr, p_poison
	STQ	xzr, c_opening
	mov	x0, 2                           // the King opens with two quick strikes
	LDQ	x8, boss
	cbnz	x8, L_first_intent
	mov	x0, 3
	bl	_rnd
L_first_intent:
	STQ	x0, c_quick_left
	bl	_prepare_intent
	LDQ	x2, m_flavor
	LOG	"\003\023  %s\001"
1:	LDQ	x8, foe_hp
	cmp	x8, 0
	b.le	90f
	LDQ	x8, p_hp
	cmp	x8, 0
	b.le	90f
	bl	_render_combat
	STR	x0, "  \003[a]ttack  [h]eavy  [g]uard  [b]ean  [p]otion  [r]un >\001 "
	mov	x1, 1
	bl	_readline
	ldrb	w19, [x0]
	cbz	w19, 10f
	ldrb	w8, [x0, 1]
	cbnz	w8, 40f
	cmp	w19, 'a'
	b.eq	10f
	cmp	w19, 'h'
	b.eq	15f
	cmp	w19, 'g'
	b.eq	18f
	cmp	w19, 'b'
	b.eq	25f
	cmp	w19, 'p'
	b.eq	20f
	cmp	w19, 'r'
	b.eq	30f
	b	40f

10:	bl	_roll_dmg                       // attack
	mov	x20, x0
	mov	x21, 0
	LDQ	x8, p_class
	cmp	x8, 2                           // rogue: 15% crit
	b.ne	12f
	mov	x0, 100
	bl	_rnd
	cmp	x0, 15
	b.hs	12f
	lsl	x20, x20, 1
	mov	x21, 1
12:	mov	x0, x20
	mov	x1, 0
	bl	_apply_hit
	cbz	x0, 11f
	mov	x3, x0
	LA	x2, m_name
	cbz	x21, 13f
	LOG	"\002\005  → Critical! You hit %s for %ld.\001"
	b	11f
13:	LOG	"\005  → You hit %s for %ld.\001"
11:	LDQ	x8, foe_hp
	cmp	x8, 0
	b.le	90f
	STR	x0, "\004  ← %s hits you for %ld.\001"
	bl	_foe_turn
	b	1b

15:	LDQ	x8, c_opening
	cbnz	x8, 17f
	mov	x0, 2                           // heavy: double damage or a miss
	bl	_rnd
	cbnz	x0, 16f
	bl	_roll_dmg
	lsl	x0, x0, 1
	mov	x1, 0
	bl	_apply_hit
	cbz	x0, 11b
	mov	x2, x0
	LOG	"\002\005  ⇒ A crushing blow! %ld damage.\001"
	b	11b
16:	LOG	"\003  You swing wide and miss.\001"
	b	11b
17:	bl	_roll_dmg                       // a parry makes the next heavy a sure hit
	lsl	x0, x0, 1
	mov	x1, 1
	bl	_apply_hit
	mov	x2, x0
	LOG	"\002\005  Riposte! You strike the opening for %ld.\001"
	b	11b
18:	mov	x0, 0
	bl	_foe_turn
	b	1b

20:	LDQ	x8, p_pot                       // potion
	cmp	x8, 0
	b.gt	21f
	LOG	"\003  No potions. Pockets full of lint.\001"
	b	1b
21:	bl	_drink_potion
	mov	x2, x0
	LOG	"\005  ✚ You drink. +%ld HP.\001"
	STR	x0, "\004  ← %s clips you for %ld mid-sip.\001"
	bl	_foe_turn
	b	1b

25:	LDQ	x8, p_beans                     // bean: +3 ATK for the fight
	cmp	x8, 0
	b.gt	26f
	LOG	"\003  No beans. A tragedy.\001"
	b	1b
26:	ADDQ	p_beans, -1
	ADDQ	c_buff, 3
	LOG	"\024  You chew a coffee bean. ATK +3 this fight. Your eye twitches.\001"
	STR	x0, "\004  ← %s hits you for %ld.\001"
	bl	_foe_turn
	b	1b

30:	LDQ	x8, m_trait                     // run
	cmp	x8, 6
	b.ne	35f
	LOG	"\004  'Before you go, quick sync?' You can't leave.\001"
	b	31f
35:	LDQ	x8, boss
	cbz	x8, 32f
	LOG	"\004  The King's gaze pins you in place.\001"
	b	31f
32:	LDQ	x8, p_class
	cmp	x8, 2                           // rogue: 75%, everyone else 50%
	b.ne	33f
	mov	x0, 4
	bl	_rnd
	cbnz	x0, 34f
	b	31f
33:	mov	x0, 2
	bl	_rnd
	cbnz	x0, 31f
34:	STQ	xzr, p_poison
	mov	x0, 1
	LEAVE
31:	STR	x0, "\004  ← You stumble. %s clips you for %ld.\001"
	bl	_foe_turn
	b	1b

40:	LOG	"\003  That's not a thing you can do.\001"
	b	1b

90:	STQ	xzr, p_poison
	LDQ	x8, p_hp
	cmp	x8, 0
	b.gt	91f
	bl	_combat_recap
	mov	x0, 2
	LEAVE
91:
	mov	x0, 0
	LEAVE

// ---------- rooms ----------

_merchant:
	ENTER
	mov	x21, 0                          // a message from the last choice?
1:	LA	x0, art_merchant
	LA	x1, lbl_merchant
	bl	_render_top
	SAY	"\023  A hooded figure unfolds a tiny table.\001\n\003  'Buying or browsing?'\001\n\n"
	cbz	x21, 2f
	LA	x1, msgbuf
	SAY	"%s\n"
2:	bl	_status                         // show purse and gear beside the prices
	SAY	"\n  \023[1]\001 Potion           \0075g\001\n  \023[2]\001 Sharpen weapon  \00712g\001  (+1 ATK)\n  \023[3]\001 Reinforce armor \00712g\001  (+1 ARM)\n  \023[4]\001 Mystery box     \00710g\001\n  \023[5]\001 Coffee beans     \0078g\001  (x2)\n  \023[6]\001 Leave\n"
	STR	x0, "  \003>\001 "
	mov	x1, 0
	bl	_readline
	mov	x21, 1
	ldrb	w8, [x0]
	cbz	w8, 50f
	ldrb	w9, [x0, 1]
	cbnz	w9, 40f
	LDQ	x22, p_gold
	cmp	w8, '1'
	b.ne	11f
	cmp	x22, 5
	b.lt	40f
	ADDQ	p_gold, -5
	ADDQ	p_pot, 1
	MSG	"\017  You pocket a potion.\001"
	b	1b
11:	cmp	w8, '2'
	b.ne	12f
	cmp	x22, 12
	b.lt	40f
	ADDQ	p_gold, -12
	ADDQ	p_atk, 1
	MSG	"\005  Sharper. Meaner.\001"
	b	1b
12:	cmp	w8, '3'
	b.ne	13f
	cmp	x22, 12
	b.lt	40f
	ADDQ	p_gold, -12
	ADDQ	p_arm, 1
	MSG	"\005  Click. Sturdier.\001"
	b	1b
13:	cmp	w8, '4'
	b.ne	14f
	cmp	x22, 10
	b.lt	40f
	ADDQ	p_gold, -10
	mov	x0, 100
	bl	_rnd
	cmp	x0, 40
	b.hs	131f
	ADDQ	p_pot, 2
	MSG	"\017  Two potions clatter out.\001"
	b	1b
131:	cmp	x0, 70
	b.hs	132f
	ADDQ	p_gold, 18
	MSG	"\007  18 gold. Don't ask.\001"
	b	1b
132:	cmp	x0, 90
	b.hs	133f
	mov	x0, 4
	bl	_hurt
	mov	x2, x0
	MSG	"\004  It bites. %ld damage.\001"
	LDQ	x8, p_hp
	cmp	x8, 0
	b.gt	1b
	LA	x1, msgbuf
	SAY	"%s\n"
	mov	x0, 1                           // a lethal bite ends shopping
	LEAVE
133:	ADDQ	p_max, 2
	ADDQ	p_hp, 2
	MSG	"\005  Max HP +2.\001"
	b	1b
14:	cmp	w8, '5'
	b.ne	15f
	cmp	x22, 8
	b.lt	40f
	ADDQ	p_gold, -8
	ADDQ	p_beans, 2
	MSG	"\024  Two beans, wrapped in a receipt.\001"
	b	1b
15:	cmp	w8, '6'
	b.eq	50f
40:	MSG	"\003  Not enough gold, or not a real choice.\001"
	b	1b
50:	LA	x0, art_merchant
	LA	x1, lbl_merchant
	bl	_render_top
	SAY	"\003  'Come back on payday.' The merchant pulls up a stool.\001\n"
	bl	_render_bottom
	mov	x0, 0
	LEAVE

// handle_room -> x0: 0 ok, 1 dead, 2 reached the exit
_handle_room:
	ENTER
	LDQ	x8, p_x
	LDQ	x9, p_y
	mov	x10, 5
	madd	x19, x9, x10, x8
	cmp	x19, 24
	b.ne	1f
	mov	x0, 2
	LEAVE
1:	LA	x20, rooms
	ldrb	w21, [x20, x19]
	cmp	w21, 1
	b.eq	30f
	cmp	w21, 2
	b.eq	40f
	cmp	w21, 3
	b.eq	50f
	cmp	w21, 4
	b.eq	60f
	cmp	w21, 5
	b.eq	70f
	cmp	w21, 6
	b.eq	80f
	cmp	w21, 7
	b.eq	85f
	cmp	w21, 8
	b.eq	90f
	cmp	w21, 9
	b.eq	100f
	cmp	w21, 10
	b.ne	2f
	add	x0, x20, x19
	bl	_crew_room
	mov	x0, 0
	LEAVE

2:	bl	_floor_scene                    // a room keeps its detail on return
	mov	x9, 3
	udiv	x8, x19, x9
	msub	x8, x8, x9, x19
	LDQ	x10, depth
	sub	x10, x10, 1
	madd	x8, x10, x9, x8
	LA	x9, quiet_lines
	ldr	x1, [x9, x8, lsl 3]
	SAY	"\003  %s\001\n"
	bl	_render_bottom
	mov	x0, 0
	LEAVE

30:	bl	_procgen_monster                // monster
300:	bl	_combat
	cmp	x0, 2
	b.ne	31f
	mov	x0, 1
	LEAVE
31:	strb	wzr, [x20, x19]
	mov	x21, x0
	cbnz	x21, 32f
	LDQ	x8, m_gold
	ADDQ	p_gold, x8
	LDQ	x0, m_gold
	bl	_gain_xp
	mov	x22, x0
32:	LA	x0, art_empty
	LA	x1, lbl_empty
	bl	_render_top
	cbz	x21, 33f
	SAY	"\003  You catch your breath. The room is quiet now.\001\n"
	b	34f
33:	bl	_combat_recap
	LA	x1, m_name
	SAY	"\005  ✓ %s collapses.\001\n"
	LDQ	x1, m_gold
	SAY	"\007  +%ld gold.\001\n"
	LDQ	x1, m_gold
	SAY	"\023  +%ld XP.\001\n"
	cbz	x22, 34f
	LDQ	x1, p_lvl
	SAY	"\002\005  ★ LEVEL UP! You are level %ld.\001\n"
34:	bl	_render_bottom
	mov	x0, 0
	LEAVE

40:	bl	_procgen_treasure               // treasure
	LDQ	x8, t_kind
	LDQ	x22, t_lo
	cbnz	x8, 41f
	mov	x0, x22
	LDQ	x1, t_hi
	bl	_randint
	mov	x22, x0
	ADDQ	p_gold, x22
	mov	x2, x22
	MSG	"\007  +%ld gold.\001"
	b	45f
41:	cmp	x8, 1
	b.ne	42f
	ADDQ	p_pot, 1
	MSG	"\017  +1 potion.\001"
	b	45f
42:	cmp	x8, 2
	b.ne	43f
	ADDQ	p_atk, x22
	mov	x2, x22
	MSG	"\005  ATK +%ld.\001"
	b	45f
43:	cmp	x8, 3
	b.ne	44f
	ADDQ	p_arm, x22
	mov	x2, x22
	MSG	"\005  Armor +%ld.\001"
	b	45f
44:	ADDQ	p_beans, x22
	mov	x2, x22
	MSG	"\024  +%ld coffee beans.\001"
45:	strb	wzr, [x20, x19]
	LA	x0, art_treasure
	LA	x1, lbl_treasure
	bl	_render_top
	LA	x1, t_name
	SAY	"  You find \007%s\001.\n"
	LA	x1, msgbuf
	SAY	"%s\n"
	bl	_render_bottom
	mov	x0, 0
	LEAVE

50:	mov	x0, 4                           // trap
	bl	_rnd
	LA	x8, traps
	mov	x9, 24
	madd	x21, x0, x9, x8
	ldr	x0, [x21, 8]
	ldr	x1, [x21, 16]
	bl	_randint
	LDQ	x8, depth
	add	x0, x0, x8
	sub	x0, x0, 1
	bl	_hurt
	mov	x22, x0
	strb	wzr, [x20, x19]
	LA	x0, art_trap
	LA	x1, lbl_trap
	bl	_render_top
	ldr	x1, [x21]
	SAY	"  %s\n"
	mov	x1, x22
	SAY	"\004  -%ld HP.\001\n"
	bl	_render_bottom
	LDQ	x8, p_hp
	cmp	x8, 0
	cset	x0, le
	LEAVE

60:	mov	x0, 3                           // shrine
	bl	_rnd
	LA	x8, shrine_lines
	ldr	x21, [x8, x0, lsl 3]
	LA	x0, art_shrine
	LA	x1, lbl_shrine
	bl	_render_top
	mov	x1, x21
	SAY	"  %s\n"
	bl	_render_bottom
	LDQ	x8, p_gold
	cmp	x8, 5
	b.lt	65f
	STR	x0, "\n  \003Offer 5 gold? [y/N] >\001 "
	mov	x1, 1
	bl	_readline
	ldrb	w8, [x0]
	cmp	w8, 'y'
	b.ne	65f
	ldrb	w8, [x0, 1]
	cbnz	w8, 65f
	ADDQ	p_gold, -5
	mov	x0, 100
	bl	_rnd
	cmp	x0, 40
	b.hs	61f
	ADDQ	p_max, 3
	ADDQ	p_hp, 3
	STR	x22, "\005  Max HP +3.\001"
	b	63f
61:	cmp	x0, 70
	b.hs	62f
	ADDQ	p_atk, 1
	STR	x22, "\005  ATK +1.\001"
	b	63f
62:	ADDQ	p_arm, 1
	STR	x22, "\005  Armor +1.\001"
63:	strb	wzr, [x20, x19]
	LA	x0, art_shrine
	LA	x1, lbl_shrine
	bl	_render_top
	mov	x1, x21
	mov	x2, x22
	SAY	"  %s\n\n%s\n"
	bl	_render_bottom
	mov	x0, 0
	LEAVE
65:
	SAY	"\003  The offering bowl stays out.\001\n"
	mov	x0, 0
	LEAVE

70:	bl	_merchant                       // merchant
	LEAVE

80:	mov	x0, 4                           // fountain
	bl	_rnd
	LA	x8, fountain_lines
	ldr	x21, [x8, x0, lsl 3]
	mov	x0, 8
	bl	_heal
	mov	x22, x0
	cbz	x22, L_fountain_full
	strb	wzr, [x20, x19]
	LA	x0, art_fountain
	LA	x1, lbl_fountain
	bl	_render_top
	mov	x1, x21
	SAY	"  %s\n"
	mov	x1, x22
	SAY	"\005  +%ld HP.\001\n"
	bl	_render_bottom
	mov	x0, 0
	LEAVE

L_fountain_full:
	LA	x0, art_fountain
	LA	x1, lbl_fountain
	bl	_render_top
	SAY	"  The dipper hangs on a hook. You're at full health.\n  You can come back for a drink.\n"
	bl	_render_bottom
	mov	x0, 0
	LEAVE

85:	LA	x0, art_campfire                // campfire
	LA	x1, lbl_campfire
	bl	_render_top
	SAY	"\006  Embers glow in a ring of stones. Someone left a kettle.\001\n"
	bl	_render_bottom
	STR	x0, "\n  \003Rest here? [y/N] >\001 "
	mov	x1, 1
	bl	_readline
	ldrb	w8, [x0]
	cmp	w8, 'y'
	b.ne	87f
	ldrb	w8, [x0, 1]
	cbnz	w8, 87f
	strb	wzr, [x20, x19]
	mov	x0, 100
	bl	_rnd
	cmp	x0, 25
	b.hs	86f
	bl	_procgen_monster                // 25%: ambushed in your sleep
	STR	x8, "You wake to something standing over you."
	STQ	x8, m_flavor
	b	300b
86:	LDQ	x8, p_max
	STQ	x8, p_hp
	LA	x0, art_campfire
	LA	x1, lbl_campfire
	bl	_render_top
	SAY	"\006  You doze by the embers. The kettle sings.\001\n\005  HP fully restored.\001\n"
	bl	_render_bottom
87:	mov	x0, 0
	LEAVE

90:	mov	x0, 10                          // riddle
	bl	_rnd
	LA	x8, riddles
	mov	x9, 24
	madd	x21, x0, x9, x8
	LA	x0, art_owl
	LA	x1, lbl_riddle
	bl	_render_top
	ldr	x1, [x21]
	SAY	"\020  An owl statue clutching a mug blinks awake.\001\n  '%s'\n"
	bl	_render_bottom
	strb	wzr, [x20, x19]
	STR	x0, "\n  \003Your answer >\001 "
	mov	x1, 1
	bl	_readline
	mov	x22, x0
	ldr	x1, [x21, 8]
	bl	_strstr
	cbnz	x0, 91f
	mov	x0, x22
	ldr	x1, [x21, 16]
	bl	_strstr
	cbnz	x0, 91f
	LDQ	x8, depth
	add	x0, x8, 3
	bl	_hurt
	mov	x23, x0
	LA	x0, art_owl
	LA	x1, lbl_riddle
	bl	_render_top
	ldr	x1, [x21, 8]
	SAY	"\003  The owl's eyes flash red. (It was '%s'.)\001\n"
	mov	x1, x23
	SAY	"\004  -%ld HP.\001\n"
	bl	_render_bottom
	LDQ	x8, p_hp
	cmp	x8, 0
	cset	x0, le
	LEAVE
91:	mov	x0, 2
	bl	_rnd
	cbnz	x0, 92f
	ADDQ	p_atk, 1
	STR	x22, "\005  ATK +1.\001"
	b	93f
92:	ADDQ	p_gold, 20
	STR	x22, "\007  +20 gold.\001"
93:	LA	x0, art_owl
	LA	x1, lbl_riddle
	bl	_render_top
	mov	x1, x22
	SAY	"\005  The owl hoots, pleased. Something clinks at your feet.\001\n%s\n"
	bl	_render_bottom
	mov	x0, 0
	LEAVE

100:	strb	wzr, [x20, x19]                 // dice goblin
	mov	x21, 0
101:	LA	x0, art_dice
	LA	x1, lbl_dice
	bl	_render_top
	SAY	"\006  A goblin in a green visor rattles two dice in a cup.\001\n\003  'Two dice each. Beat my roll and I double your bet.'\001\n\n"
	cbz	x21, 102f
	LA	x1, msgbuf
	SAY	"%s\n"
102:	LDQ	x8, p_gold
	cmp	x8, 5
	b.ge	103f
	SAY	"\n\003  You're broke. The goblin loses interest.\001\n"
	bl	_render_bottom
	mov	x0, 0
	LEAVE
103:	LDQ	x1, p_gold
	SAY	"\007  Your purse: %ld gold.\001\n\n  \023[1]\001 Bet  \0075g\001\n  \023[2]\001 Bet \00710g\001\n  \023[3]\001 Bet \00720g\001\n  \023[4]\001 Walk away\n"
	STR	x0, "  \003>\001 "
	mov	x1, 0
	bl	_readline
	mov	x21, 1
	ldrb	w8, [x0]
	cbz	w8, 109f
	ldrb	w9, [x0, 1]
	cbnz	w9, 104f
	mov	x22, 5
	cmp	w8, '1'
	b.eq	105f
	mov	x22, 10
	cmp	w8, '2'
	b.eq	105f
	mov	x22, 20
	cmp	w8, '3'
	b.eq	105f
	cmp	w8, '4'
	b.eq	109f
104:	MSG	"\003  The goblin waits for a real bet.\001"
	b	101b
105:	LDQ	x8, p_gold
	cmp	x8, x22
	b.ge	106f
	MSG	"\003  You can't cover that.\001"
	b	101b
106:	mov	x0, 6                           // 2d6 each
	bl	_rnd
	mov	x23, x0
	mov	x0, 6
	bl	_rnd
	add	x23, x23, x0
	add	x23, x23, 2
	mov	x0, 6
	bl	_rnd
	mov	x24, x0
	mov	x0, 6
	bl	_rnd
	add	x24, x24, x0
	add	x24, x24, 2
	mov	x2, x23
	mov	x3, x24
	mov	x4, x22
	cmp	x23, x24
	b.gt	107f
	b.lt	108f
	MSG	"\003  You roll %ld, it rolls %ld. A push.\001"
	b	101b
107:	ADDQ	p_gold, x22
	MSG	"\005  You roll %ld, it rolls %ld. +%ld gold!\001"
	b	101b
108:	LDQ	x8, p_gold
	sub	x8, x8, x22
	STQ	x8, p_gold
	MSG	"\004  You roll %ld, it rolls %ld. -%ld gold.\001"
	b	101b
109:	LA	x0, art_empty
	LA	x1, lbl_empty
	bl	_render_top
	SAY	"\003  The goblin tips its visor. 'Come back richer.'\001\n"
	bl	_render_bottom
	mov	x0, 0
	LEAVE

// Night shift: each floor has one crew member. Leaving keeps the room active.
// crew_choice -> 1 or 2, or 0 to come back later.
_crew_choice:
	ENTER
1:	STR	x0, "  \003[1/2/l] >\001 "
	mov	x1, 1
	bl	_readline
	ldrb	w8, [x0]
	cbz	w8, 2f
	ldrb	w9, [x0, 1]
	cbnz	w9, 3f
	cmp	w8, 'l'
	b.eq	2f
	sub	w8, w8, '1'
	cmp	w8, 1
	b.hi	3f
	add	w0, w8, 1
	LEAVE
2:	mov	x0, 0
	LEAVE
3:	SAY	"\003  Choose 1, 2, or l to come back later.\001\n"
	b	1b

// crew_room(x0 address of room byte). Clear the landmark only on rescue.
_crew_room:
	ENTER
	mov	x19, x0
	LDQ	x20, depth
	cmp	x20, 2
	b.eq	Lcrew_fitter
	b.hi	Lcrew_taster
	LA	x0, art_lift
	STR	x1, "\002\006  THE SACK LIFT\001\n"
	bl	_render_top
	SAY	"  A split axle pins Nell's boot under her delivery cart.\n  'Cut the sacks if you have to. Just mind the toes.'\n\n"
	bl	_status
	SAY	"\n  [1] Slit the sacks. Catch two beans before they spill.\n  [2] Lift the loaded cart. 4 HP for Nell's leather harness (+1 ARM).\n  [l] Come back later.\n"
1:	bl	_crew_choice
	cbz	x0, Lcrew_later
	cmp	x0, 2
	b.ne	2f
	LDQ	x8, p_hp
	cmp	x8, 4
	b.gt	3f
	SAY	"\003  Your knees give. You need at least 5 HP to lift it.\001\n"
	b	1b
3:	ADDQ	p_hp, -4
	ADDQ	p_arm, 1
	SAY	"\n  You heave. Nell rolls clear and buckles her harness over your coat.\n\005  Nell is free. -4 HP, +1 ARM.\001\n"
	b	Lcrew_rescued
2:	ADDQ	p_beans, 2
	SAY	"\n  Beans pour down the chute. Nell slips out and palms you two.\n\005  Nell is free. +2 beans.\001\n"
	b	Lcrew_rescued

Lcrew_fitter:
	LA	x0, art_manifold
	STR	x1, "\002\020  THE BLEED VALVES\001\n"
	bl	_render_top
	SAY	"  Ivo is wedged behind a buckled boiler door. He taps on the brass.\n  'Bleed the one with more pressure. Both wheels open the door,\n  but guess wrong and you'll take a faceful of steam.'\n\n"
	mov	x0, 2
	bl	_rnd
	add	x21, x0, 1                      // which valve is under full pressure?
	mov	x1, 90
	mov	x2, 20
	cmp	x21, 1
	b.eq	4f
	mov	x1, 20
	mov	x2, 90
4:	SAY	"  \006BRASS  %ld psi       IRON  %ld psi\001\n\n"
	SAY	"  [1] Vent brass.    [2] Vent iron.    [l] Come back later.\n"
	bl	_crew_choice
	cbz	x0, Lcrew_later
	cmp	x0, x21
	b.eq	5f
	LDQ	x8, p_hp                        // the steam scalds, but never kills
	sub	x8, x8, 1
	mov	x9, 3
	cmp	x8, x9
	csel	x9, x8, x9, lt
	mov	x1, x9
	LDQ	x8, p_hp
	sub	x8, x8, x9
	STQ	x8, p_hp
	SAY	"\n  The door flies open. Ivo pulls you out of the steam.\n\004  Ivo is free. The backwash costs you %ld HP.\001\n"
	b	Lcrew_rescued
5:	ADDQ	p_atk, 1
	SAY	"\n  The needle drops. Ivo steps out and hands you his long brass wrench.\n\005  Ivo is free. +1 ATK.\001\n"
	b	Lcrew_rescued

Lcrew_taster:
	LA	x0, art_hatch
	STR	x1, "\002\017  THE TASTING HATCH\001\n"
	bl	_render_top
	SAY	"  The King locked Dot in the dumbwaiter between courses. You prise\n  the hatch up a crack. 'Hands full,' she whispers. 'Pick one tray\n  and I'll drop the other.'\n\n"
	bl	_status
	SAY	"\n  [1] Save two stoppered potions for later.\n  [2] Drink the cordial now (+3 max HP, heal up to 8 HP).\n  [l] Come back with both hands free.\n"
	bl	_crew_choice
	cbz	x0, Lcrew_later
	cmp	x0, 2
	b.eq	6f
	ADDQ	p_pot, 2
	SAY	"\n  Glass breaks down the shaft. Dot ducks under your arm with both bottles.\n\005  Dot is free. +2 potions.\001\n"
	b	Lcrew_rescued
6:	ADDQ	p_max, 3
	mov	x0, 8
	bl	_heal
	mov	x1, x0
	SAY	"\n  Dot lifts the cordial to your lips, then climbs over you to freedom.\n  'He thought that one was poison. Funny man.'\n\005  Dot is free. +3 max HP, +%ld HP.\001\n"
Lcrew_rescued:
	sub	x8, x20, 1
	mov	x9, 1
	lsl	x9, x9, x8
	LDQ	x8, crew_mask
	orr	x8, x8, x9
	STQ	x8, crew_mask
	strb	wzr, [x19]
	bl	_render_bottom
	LEAVE
Lcrew_later:
	SAY	"\003  You leave the way clear. You can return on this floor.\001\n"
	bl	_render_bottom
	LEAVE

_crew_ending:
	ENTER
	LDQ	x19, crew_mask
	cbz	x19, 4f
	cmp	x19, 7
	b.eq	5f
	tbz	x19, 0, 1f
	SAY	"  Nell rolls the royal sacks up to the dock. 'No delivery charge.'\n"
1:	tbz	x19, 1, 2f
	SAY	"  Ivo takes the whistle off the King's kettle. He's had enough of that noise.\n"
2:	tbz	x19, 2, 3f
	SAY	"  Dot throws the tasting spoon down the well. She'll drink when she's thirsty.\n"
3:	LEAVE
4:	SAY	"\003  On your way out, three timecards still hang on the IN side.\001\n"
	LEAVE
5:	SAY	"\007  Nell props the loading hatch open. Ivo lights the stove.\n  Dot sets out four cups and grinds the bean. The first pot is weak.\n  Everyone stays for a second cup.\001\n"
	LEAVE

// ---------- main loop ----------

// best_path -> x0 "$HOME/.crypt-best", or 0 without HOME
_best_path:
	ENTER
	STR	x0, "HOME"
	bl	_getenv
	cbz	x0, 1f
	mov	x2, x0
	LA	x0, pathbuf
	STR	x1, "%s/.crypt-best"
	bl	_sfmt
	LA	x0, pathbuf
	LEAVE
1:	mov	x0, 0
	LEAVE

_best_load:
	ENTER
	bl	_best_path
	cbz	x0, 1f
	STR	x1, "r"
	bl	_fopen
	cbz	x0, 1f
	mov	x19, x0
	LA	x0, tmpc
	mov	w1, 64
	mov	x2, x19
	bl	_fgets
	mov	x20, x0
	mov	x0, x19
	bl	_fclose
	cbz	x20, 1f
	LA	x0, tmpc
	mov	x1, 0
	mov	w2, 10
	bl	_strtol
	STQ	x0, best
1:	LEAVE

// finish(x0 won?): score = 100/floor cleared + 25/level + gold (+500 for the King)
_finish:
	ENTER
	mov	x19, x0
	LDQ	x8, depth
	sub	x8, x8, 1
	mov	x9, 100
	mul	x20, x8, x9
	LDQ	x8, p_lvl
	mov	x9, 25
	madd	x20, x8, x9, x20
	LDQ	x8, p_gold
	add	x20, x20, x8
	mov	x9, 500
	cmp	x19, 0
	csel	x9, x9, xzr, ne
	add	x20, x20, x9
	mov	x1, x20
	SAY	"\002\023  Score: %ld\001"
	LDQ	x8, best
	cmp	x20, x8
	b.le	2f
	SAY	"   \002\007NEW BEST!\001"
	STQ	x20, best
	bl	_best_path
	cbz	x0, 2f
	STR	x1, "w"
	bl	_fopen
	cbz	x0, 2f
	mov	x21, x0
	LA	x0, tmpc
	STR	x1, "%ld\n"
	mov	x2, x20
	bl	_sfmt
	LA	x0, tmpc
	mov	x1, x21
	bl	_fputs
	mov	x0, x21
	bl	_fclose
2:	LDQ	x1, run_seed
	SAY	"\n\003  Replay this run: ./crypt --seed %lu\001\n\n"
	LEAVE

// The floor's 22 ordinary rooms form a shuffled deck. The last slot is
// reserved so a crew room can swap into a side aisle without erasing loot.
_gen_dungeon:
	ENTER
	LA	x19, rooms
	LA	x20, visited
	stp	xzr, xzr, [x20]
	stp	xzr, xzr, [x20, 16]             // visited has 32 bytes
	mov	w8, 1
	strb	w8, [x20]
	strb	wzr, [x19]                      // entrance
	strb	wzr, [x19, 24]                  // stairs / throne
	LDQ	x8, depth
	sub	x8, x8, 1
	mov	x9, 22
	LA	x10, floor_decks
	madd	x1, x8, x9, x10
	add	x0, x19, 1
	mov	x2, 22
	bl	_memcpy
	mov	x21, 22
1:	mov	x0, x21                         // shuffle slots 1 through 22
	bl	_rnd
	add	x0, x0, 1
	ldrb	w8, [x19, x0]
	ldrb	w9, [x19, x21]
	strb	w8, [x19, x21]
	strb	w9, [x19, x0]
	sub	x21, x21, 1
	cmp	x21, 1
	b.hi	1b
	mov	x0, 8
	bl	_rnd
	LA	x8, crew_aisles
	ldrb	w9, [x8, x0]
	ldrb	w10, [x19, x9]
	strb	w10, [x19, 23]
	mov	w10, 10
	strb	w10, [x19, x9]
	LEAVE

_play:
	ENTER
	bl	_clear
	LA	x0, art_banner
	bl	_show_art
	LDQ	x1, run_seed
	SAY	"\n\003  Run seed: %lu\001\n"
	bl	_best_load
	LDQ	x1, best
	cbz	x1, 49f
	SAY	"\003  Best score: %ld\001\n\n"
49:
	STR	x0, "\020  Adventurer's name: \001"
	mov	x1, 0
	bl	_readline
	ldrb	w8, [x0]
	cbnz	w8, 1f
	STR	x0, "Beans"
1:	mov	x1, x0
	LA	x0, p_name
	mov	x2, 256
	bl	_strlcpy
	SAY	"\n  \023Choose your calling:\001\n  \023[1]\001 Knight    \003+1 ARM, +4 max HP\001\n  \023[2]\001 Barista   \003+2 potions, and they heal 15\001\n  \023[3]\001 Rogue     \003+1 ATK, 15%% crits, flees 75%% of the time\001\n"
50:	STR	x0, "  \003[1-3] >\001 "
	mov	x1, 0
	bl	_readline
	ldrb	w8, [x0]
	mov	x9, 0
	cbz	w8, 51f
	ldrb	w10, [x0, 1]
	cbnz	w10, 50b
	sub	w9, w8, '1'
	cmp	w9, 2
	b.hi	50b
51:	STQ	x9, p_class

	mov	x8, 20
	STQ	x8, p_hp
	STQ	x8, p_max
	mov	x8, 4
	STQ	x8, p_atk
	STQ	xzr, p_arm
	mov	x8, 5
	STQ	x8, p_gold
	mov	x8, 1
	STQ	x8, p_pot
	STQ	xzr, p_x
	STQ	xzr, p_y
	STQ	xzr, p_turns
	STQ	xzr, crew_mask

	mov	x8, 1
	STQ	x8, p_lvl
	STQ	x8, depth
	STQ	xzr, p_xp
	STQ	xzr, boss
	STQ	x8, p_beans
	LDQ	x8, p_class
	cmp	x8, 0
	b.ne	52f
	mov	x8, 1                           // knight
	STQ	x8, p_arm
	ADDQ	p_max, 4
	ADDQ	p_hp, 4
	b	54f
52:	cmp	x8, 1
	b.ne	53f
	ADDQ	p_pot, 2                        // barista
	b	54f
53:	ADDQ	p_atk, 1                        // rogue
54:	bl	_deal_floor

	bl	_floor_scene
	LA	x1, p_name
	LDQ	x8, p_class
	LA	x9, class_names
	ldr	x2, [x9, x8, lsl 3]
	SAY	"\023  %s the %s ducks under the dock chain.\001\n  The King's taken every bean north of the river.\n  His last one's three floors down. Take it back.\n\020  Hear that knock? Follow ! to find the night shift.\001\n"
	bl	_render_bottom

10:	LDQ	x8, p_hp
	cmp	x8, 0
	b.le	20f
	STR	x0, "\n  \003[w/a/s/d] move  [p]otion  [i] info  [q] quit >\001 "
	mov	x1, 1
	bl	_readline
	ldrb	w8, [x0]
	cbz	w8, 15f
	ldrb	w9, [x0, 1]
	cbnz	w9, 15f
	cmp	w8, 'q'
	b.eq	18f
	cmp	w8, 'i'
	b.eq	17f
	cmp	w8, 'p'
	b.eq	L_field_potion
	mov	x0, 0
	mov	x1, 0
	cmp	w8, 'w'
	b.ne	11f
	mov	x1, 1
	b	14f
11:	cmp	w8, 's'
	b.ne	12f
	mov	x1, -1
	b	14f
12:	cmp	w8, 'a'
	b.ne	13f
	mov	x0, -1
	b	14f
13:	cmp	w8, 'd'
	b.ne	15f
	mov	x0, 1
14:	LDQ	x2, p_x
	LDQ	x3, p_y
	add	x2, x2, x0
	add	x3, x3, x1
	cmp	x2, 4                           // unsigned: -1 is out of bounds too
	b.hi	16f
	cmp	x3, 4
	b.hi	16f
	STQ	x2, p_x
	STQ	x3, p_y
	ADDQ	p_turns, 1
	mov	x8, 5
	madd	x8, x3, x8, x2
	LA	x9, visited
	mov	w10, 1
	strb	w10, [x9, x8]
	bl	_handle_room
	cmp	x0, 1
	b.eq	20f
	cmp	x0, 2
	b.eq	30f
	b	10b
15:	SAY	"\003  Move with w/a/s/d. Press i for the shift notes.\001\n"
	b	10b
16:	SAY	"\003  A wall. Rude.\001\n"
	b	10b
17:	bl	_clear
	LDQ	x1, run_seed
	SAY	"\002  Shift notes\001   \003Seed %lu\001\n  The far stair (>) leads down. Your map remembers nearby doors.\n  Follow ! to a missing worker before you leave their floor.\n  Shops stay open. A quiet doorway can still hide a trap.\n  In a fight, [g]uard a wind-up, then [h]eavy to riposte.\n"
	bl	_render_bottom
	b	10b
L_field_potion:
	LDQ	x8, p_hp
	LDQ	x9, p_max
	cmp	x8, x9
	b.lt	L_field_stock
	SAY	"\003  You're at full health. The cork stays in.\001\n"
	b	10b
L_field_stock:
	LDQ	x8, p_pot
	cbnz	x8, L_field_drink
	SAY	"\003  You're out of potions.\001\n"
	b	10b
L_field_drink:
	bl	_drink_potion
	mov	x1, x0
	LDQ	x2, p_hp
	LDQ	x3, p_max
	LDQ	x4, p_pot
	SAY	"\005  +%ld HP.\001  Health %ld/%ld, potions left %ld.\n"
	b	10b
18:	SAY	"\003\n  You walk back into the daylight. Story untold.\001\n"
	LEAVE

20:	SAY	"\n"                            // death
	bl	_divider
	STR	x0, "\004  You crumple. The King sips, somewhere, smug.\001\n"
	bl	_slow
	LDQ	x1, depth
	LDQ	x2, p_lvl
	LDQ	x3, p_turns
	LDQ	x4, p_gold
	STR	x0, "\003  Final: floor %ld, level %ld, turn %ld, gold %ld.\001\n"
	bl	_slow
	bl	_divider
	mov	x0, 0
	bl	_finish
	LEAVE

30:	LDQ	x8, depth
	cmp	x8, 3
	b.ge	35f
	bl	_clear                          // stairs down
	LA	x0, art_stairs
	bl	_show_art
	SAY	"\n"
	bl	_divider
	STR	x0, "\007  The brass handrail is warm. Warmer still a few steps down.\001\n"
	bl	_slow
	bl	_divider
	STR	x0, "\n  \003[enter] descend  [b]ack >\001 "
	bl	_confirm_exit
	cbz	x0, L_turn_back
	ADDQ	depth, 1
	bl	_deal_floor
	STQ	xzr, p_x
	STQ	xzr, p_y
	bl	_floor_scene
	LDQ	x8, depth
	cmp	x8, 2
	b.ne	L_pantry_arrival
	SAY	"  Someone wedged a teaspoon in the safety valve.\n  The brass floor plates rattle under your boots.\n"
	b	L_floor_arrival_map
L_pantry_arrival:
	SAY	"  Every jar bears the same seal: FOR HIS MAJESTY.\n  Behind the throne door (>) a spoon taps china.\n"
L_floor_arrival_map:
	bl	_render_bottom
	b	10b

35:	bl	_clear                          // the King
	LA	x0, art_king
	bl	_show_art
	SAY	"\n"
	bl	_divider
	STR	x0, "\007  A throne of burlap sacks. On it, steaming, the King.\001\n"
	bl	_slow
	STR	x0, "\004  'You came for my last bean? Come and take it.'\001\n"
	bl	_slow
	bl	_divider
	STR	x0, "\n  \003[enter] fight  [b]ack >\001 "
	bl	_confirm_exit
	cbz	x0, L_turn_back
	bl	_setup_boss
	bl	_combat
	cmp	x0, 2
	b.eq	20b

	bl	_clear                          // victory
	LA	x0, art_exit
	bl	_show_art
	SAY	"\n"
	bl	_divider
	bl	_combat_recap
	STR	x0, "\007  The King slumps into his sacks. Behind the throne: a kitchen.\001\n"
	bl	_slow
	STR	x0, "\007  On the counter: the King's last bean.\001\n"
	bl	_slow
	STR	x0, "\002\007  You take it.\001\n"
	bl	_slow
	bl	_crew_ending
	bl	_divider
	SAY	"\n"
	LDQ	x1, p_turns
	LDQ	x2, p_lvl
	LDQ	x3, p_gold
	LDQ	x4, p_hp
	SAY	"\002\005  ★ VICTORY in %ld turns at level %ld, with %ld gold and %ld HP.\001\n\n"
	mov	x0, 1
	bl	_finish
99:	LEAVE

L_turn_back:
	SAY	"\003  You step back onto the landing.\001\n"
	bl	_render_bottom
	b	10b

// Empty input crosses the threshold. Only explicit 'b' backs away.
_confirm_exit:
	ENTER
	mov	x19, x0
	LDQ	x8, depth
	sub	x8, x8, 1
	LDQ	x9, crew_mask
	lsr	x9, x9, x8
	tbnz	x9, 0, 1f
	SAY	"\020  You can still hear someone working on this floor.\001\n"
1:	mov	x0, x19
	mov	x1, 1
	bl	_readline
	ldrb	w8, [x0]
	cbz	w8, 2f
	cmp	w8, 'b'
	b.ne	1b
	ldrb	w8, [x0, 1]
	cbnz	w8, 1b
	mov	x0, 0
	LEAVE
2:	mov	x0, 1
	LEAVE

	.globl _main
_main:
	ENTER
	mov	x19, x0                          // argc, argv
	mov	x20, x1
	cmp	w19, 1
	b.eq	L_random_seed
	ldr	x0, [x20, 8]
	STR	x1, "--help"
	bl	_strcmp
	cbnz	w0, L_seed_arg
	cmp	w19, 2
	b.ne	L_bad_seed
	mov	x21, 0
	b	L_usage
L_seed_arg:
	cmp	w19, 3
	b.ne	L_bad_seed
	ldr	x0, [x20, 8]
	STR	x1, "--seed"
	bl	_strcmp
	cbnz	w0, L_bad_seed
	ldr	x9, [x20, 16]
	ldrb	w10, [x9]
	cbz	w10, L_bad_seed
	mov	x8, 0
	mov	x11, 10
L_seed_digit:
	ldrb	w10, [x9], 1
	cbz	w10, L_seed_ready
	sub	w10, w10, '0'
	cmp	w10, 9
	b.hi	L_bad_seed
	madd	x8, x8, x11, x10
	lsr	x12, x8, 32
	cbnz	x12, L_bad_seed
	b	L_seed_digit
L_bad_seed:
	mov	x21, 2
L_usage:
	SAY	"Usage: ./crypt [--seed N]\nN is a decimal number from 0 to 4294967295.\n"
	mov	x0, x21
	LEAVE
L_random_seed:
	bl	_arc4random
	mov	w8, w0
L_seed_ready:
	STQ	x8, run_seed
	STQ	x8, rng_state
	mov	w0, 1
	bl	_isatty
	cbz	w0, 1f
	STR	x0, "TERM"
	bl	_getenv
	cbz	x0, 2f
	STR	x1, "dumb"
	bl	_strcmp
	cbz	w0, 1f
2:	mov	x8, 1
	STQ	x8, use_color
1:	mov	w0, 2                           // SIGINT
	LA	x1, _on_int
	bl	_signal
	bl	_play
	mov	w0, 0
	LEAVE

// ---------- state ----------

	.section __TEXT,__cstring,cstring_literals
L_a:	.asciz "a"
L_an:	.asciz "an"

	.data
	.p2align 3
use_color:	.quad 0
run_seed:	.quad 0
rng_state:	.quad 0
rng_step:	.quad 0x9e3779b97f4a7c15
rng_mix1:	.quad 0xbf58476d1ce4e5b9
rng_mix2:	.quad 0x94d049bb133111eb
p_hp:		.quad 0
p_max:		.quad 0
p_atk:		.quad 0
p_arm:		.quad 0
p_gold:		.quad 0
p_pot:		.quad 0
p_x:		.quad 0
p_y:		.quad 0
p_turns:	.quad 0
m_hp:		.quad 0
m_atk:		.quad 0
m_gold:		.quad 0
m_flavor:	.quad 0
m_art:		.quad 0
foe_hp:		.quad 0
log_n:		.quad 0
t_kind:		.quad 0
t_lo:		.quad 0
t_hi:		.quad 0
p_lvl:		.quad 0
p_xp:		.quad 0
depth:		.quad 0
boss:		.quad 0
c_quick_left:	.quad 0
c_windup:	.quad 0
c_incoming:	.quad 0
c_opening:	.quad 0
boss_healed:	.quad 0
m_trait:	.quad 0
p_class:	.quad 0
p_beans:	.quad 0
crew_mask:	.quad 0                         // bit depth-1 is set on rescue
p_poison:	.quad 0
c_buff:		.quad 0
best:		.quad 0

.zerofill __DATA,__bss,p_name,256,3
.zerofill __DATA,__bss,m_name,256,3
.zerofill __DATA,__bss,t_name,256,3
.zerofill __DATA,__bss,upbuf,256,3
.zerofill __DATA,__bss,msgbuf,256,3
.zerofill __DATA,__bss,tmpa,256,3
.zerofill __DATA,__bss,tmpb,256,3
.zerofill __DATA,__bss,tmpc,256,3
.zerofill __DATA,__bss,pathbuf,256,3
.zerofill __DATA,__bss,logbuf,1024,3
.zerofill __DATA,__bss,rooms,32,3
.zerofill __DATA,__bss,visited,32,3
.zerofill __DATA,__bss,inbuf,512,3
.zerofill __DATA,__bss,slowbuf,1024,3
.zerofill __DATA,__bss,fmtbuf,4096,3
.zerofill __DATA,__bss,outbuf,65536,3

// ---------- data ----------

	.section __TEXT,__cstring,cstring_literals
art_lift:	.ascii "\006"
	.ascii "           |                  |\n"
	.ascii "           |   (_)  (_)  (_)  |     No. 4 freight lift\n"
	.ascii "           |  [============]  |\n"
	.ascii "           |___O_________//___|\n"
	.asciz "\001"
art_manifold:	.ascii "\020"
	.ascii "             .---.     .---.\n"
	.ascii "            ( PSI )   ( PSI )\n"
	.ascii "          ===='|=========|'====\n"
	.ascii "              (X)       (X)\n"
	.asciz "\001"
art_hatch:	.ascii "\017"
	.ascii "             +-----------+\n"
	.ascii "             |=== SERVE =|\n"
	.ascii "             |    o o    |\n"
	.ascii "             +--(m)-(m)--+\n"
	.asciz "\001"
art_banner:
	.ascii "\021        (   )\n"
	.ascii "         ) (\n"
	.ascii "\007     \\_/\\_/\\_/──╮    \023CRYPT OF THE\n"
	.ascii "\007      │     │  ╭╯    \002CAFFEINATED KING\001\n"
	.ascii "\007      ╰─────╯──╯\n"
	.asciz "\021     ━━━━━━━━━━━\001\n"
art_dock:
	.ascii "\024       ┌──────────────┐\n"
	.ascii "       │         ╲    ║\n"
	.ascii "       J    ╔═╦═╗ ╲   ║\n"
	.ascii "        ╔═╦═╬═╬═╣     ║\n"
	.asciz "     ═══╩═╩═╩═╩═╩═════╩═\016≈≈≈\001\n"
art_boiler:
	.ascii "\021       ╔══╤══╗      \023) )\n"
	.ascii "\021       ║  ┴  ║   ╭───────╮\n"
	.ascii "     ══╣     ╚═══╡   \007◴\021   ╞══\n"
	.ascii "       ║         ╰─┬───┬─╯\n"
	.asciz "\004                   ^^^^^\001\n"
art_pantry:
	.ascii "\024     ╔═══════════════════╗\n"
	.ascii "     ║  ┌─┐   ┌─┐   ┌─┐  ║\n"
	.ascii "     ║  │\007◆\024│   │\007◆\024│   │\007◆\024│  ║\n"
	.ascii "     ╠══╧═╧═══╧═╧═══╧═╧══╣\n"
	.asciz "     ║   [--]     [--]   ║\001\n"
lbl_dock:	.asciz "\002\024  I   LOADING DOCK\001\n"
lbl_boiler:	.asciz "\002\004  II  BOILERWORKS\001\n"
lbl_pantry:	.asciz "\002\007  III KING'S PANTRY\001\n"
L_dock_scale:	.asciz "The cargo scales swing. Both pans are empty."
L_dock_book:	.asciz "A rat signed for the last load. Neat handwriting."
L_dock_cart:	.asciz "Cart tracks lead in. Bare footprints lead out."
L_boiler_steam:	.asciz "A pinhole in a pipe whistles through its teeth."
L_boiler_mug:	.asciz "Someone's keeping a mug warm on the steam return."
L_boiler_bell:	.asciz "The gauge has two marks: HOT and YOUR PROBLEM."
L_pantry_jar:	.asciz "One biscuit sits on a velvet cushion behind glass."
L_pantry_spoon:	.asciz "Each silver spoon is chained to its own hook."
L_pantry_tin:	.asciz "A tin marked DECAF is full of nails."
art_empty:	.ascii "\022"
	.ascii "            .   .   .\n"
	.ascii "              .\n"
	.ascii "            .       .\n"
	.ascii "              dust\n"
	.ascii "              ...\n"
	.asciz "\001"
art_treasure:	.ascii "\007"
	.ascii "            _______\n"
	.ascii "           /  $ $  \\\n"
	.ascii "          |  $   $  |\n"
	.ascii "           \\_______/\n"
	.ascii "            ¯¯¯¯¯¯¯\n"
	.asciz "\001"
art_trap:	.ascii "\017"
	.ascii "           \\  |  |  /\n"
	.ascii "            \\ | | /\n"
	.ascii "            --v v--\n"
	.ascii "             SNAP!\n"
	.asciz "\001"
art_shrine:	.ascii "\020"
	.ascii "              *\n"
	.ascii "             / \\\n"
	.ascii "            /   \\         humming.\n"
	.ascii "           /  ☕  \\\n"
	.ascii "           \\-----/\n"
	.asciz "\001"
art_fountain:	.ascii "\016"
	.ascii "            ~   ~   ~\n"
	.ascii "           (    o    )\n"
	.ascii "            \\_______/\n"
	.ascii "              | |\n"
	.asciz "\001"
art_merchant:	.ascii "\006"
	.ascii "            _______\n"
	.ascii "           |  o_o  |     \"buying or browsing?\"\n"
	.ascii "           |_______|\n"
	.ascii "              | |\n"
	.ascii "              | $ |\n"
	.asciz "\001"
art_exit:	.ascii "\007"
	.ascii "           ___________\n"
	.ascii "          |   _____   |\n"
	.ascii "          |  |     |  |     light leaks\n"
	.ascii "          |  |  >  |  |     from below.\n"
	.ascii "          |  |_____|  |\n"
	.ascii "          |___________|\n"
	.asciz "\001"
art_sleepy_goblin:	.ascii "\005"
	.ascii "             ___\n"
	.ascii "            / o o\\          zzz...\n"
	.ascii "           |   _   |\n"
	.ascii "            \\_____/\n"
	.asciz "\001"
art_skeleton:	.ascii "\023"
	.ascii "            .-----.\n"
	.ascii "           ( o   o )       *rattle*\n"
	.ascii "            \\  -  /\n"
	.ascii "            /| | |\\\n"
	.asciz "\001"
art_giant_rat:	.ascii "\024"
	.ascii "              __\n"
	.ascii "             ( • •)__\n"
	.ascii "              \\      \\\n"
	.ascii "               ¯¯¯¯¯¯\n"
	.asciz "\001"
art_cursed_barista:	.ascii "\004"
	.ascii "            _________\n"
	.ascii "           |#########|       \"oat milk?\"\n"
	.ascii "           |   x x   |\n"
	.ascii "           |    -    |\n"
	.ascii "            \\_______/\n"
	.asciz "\001"
art_slime:	.ascii "\005"
	.ascii "            _________\n"
	.ascii "           /         \\         *gloop*\n"
	.ascii "          | o       o |\n"
	.ascii "           \\    _    /\n"
	.ascii "            ¯¯¯¯¯¯¯¯¯\n"
	.asciz "\001"
art_shadow_imp:	.ascii "\017"
	.ascii "            #######\n"
	.ascii "           # o   o #         *flicker*\n"
	.ascii "           #   v   #\n"
	.ascii "            #######\n"
	.asciz "\001"
art_espresso_golem:	.ascii "\004"
	.ascii "           ===========\n"
	.ascii "           ||  # #  ||        PSSSSST\n"
	.ascii "           ||   v   ||\n"
	.ascii "           ===========\n"
	.ascii "           || ::::: ||\n"
	.ascii "           ===========\n"
	.asciz "\001"
lbl_empty:	.asciz "\002\021  ·  EMPTY ROOM\001\n"
lbl_monster:	.asciz "\002\004  ⚔  ENCOUNTER\001\n"
lbl_treasure:	.asciz "\002\007  ◆  TREASURE\001\n"
lbl_trap:	.asciz "\002\017  ☠  TRAP\001\n"
lbl_shrine:	.asciz "\002\020  ✦  SHRINE\001\n"
lbl_fountain:	.asciz "\002\016  ≈  FOUNTAIN\001\n"
lbl_merchant:	.asciz "\002\006  $  MERCHANT\001\n"
lbl_exit:	.asciz "\002\007  >  EXIT\001\n"
art_campfire:	.ascii "\007"
	.ascii "              (\n"
	.ascii "             ) )\n"
	.ascii "            ( ( (\n"
	.ascii "           .-'-'-.\n"
	.ascii "          '~~~~~~~'\n"
	.asciz "\001"
art_owl:	.ascii "\020"
	.ascii "             ___\n"
	.ascii "            (o,o)       \"answer me this.\"\n"
	.ascii "            {`\"'}\n"
	.ascii "            -\"-\"-\n"
	.asciz "\001"
art_stairs:	.ascii "\021"
	.ascii "           _______\n"
	.ascii "          |_____  |\n"
	.ascii "              |__ |___\n"
	.ascii "                 |___ |___\n"
	.ascii "                     |____|\n"
	.asciz "\001"
art_king:	.ascii "\007"
	.ascii "             _/\\_/\\_/\\_\n"
	.ascii "            |          |       \"MORE.\"\n"
	.ascii "            |  (o)(o)  |\n"
	.ascii "            |    __    |\n"
	.ascii "             \\  \\__/  /\n"
	.ascii "          ____\\______/____\n"
	.ascii "         /  ~  K I N G  ~  \\\n"
	.asciz "\001"
lbl_campfire:	.asciz "\002\006  ♨  CAMPFIRE\001\n"
lbl_riddle:	.asciz "\002\020  ?  RIDDLE\001\n"
art_french_press:	.ascii "\021"
	.ascii "             _____\n"
	.ascii "            |=====|o      *plunge*\n"
	.ascii "            |:::::|\n"
	.ascii "            |:::::|\n"
	.ascii "            |_____|\n"
	.asciz "\001"
art_weevils:	.ascii "\024"
	.ascii "          .  ,  .  ,  .\n"
	.ascii "         ,  °o°  °o°  ,     *skitter*\n"
	.ascii "          .  °o°  °o°  .\n"
	.ascii "         '  ,  '  ,  '\n"
	.asciz "\001"
art_lich:	.ascii "\023"
	.ascii "             .-'''-.\n"
	.ascii "            /  ~ ~  \\      *froth*\n"
	.ascii "           |  (o o)  |\n"
	.ascii "            \\   ~   /\n"
	.ascii "            /`-----'\\\n"
	.asciz "\001"
art_dice:	.ascii "\023"
	.ascii "           .-------.    .-------.\n"
	.ascii "           | o   o |    | o     |\n"
	.ascii "           |   o   |    |   o   |\n"
	.ascii "           | o   o |    |     o |\n"
	.ascii "           '-------'    '-------'\n"
	.asciz "\001"
lbl_dice:	.asciz "\002\006  ⚅  DICE GOBLIN\001\n"
art_manager:	.ascii "\023"
	.ascii "             _______\n"
	.ascii "            |  ___  |\n"
	.ascii "            | (o o) |     \"per my last email.\"\n"
	.ascii "            |  ---  |\n"
	.ascii "             \\_____/\n"
	.ascii "            /|  |  |\\    __\n"
	.ascii "           / |  V  | \\  |==|\n"
	.asciz "\001"
esc_R:	.asciz "\033[0m"
esc_B:	.asciz "\033[1m"
esc_DIM:	.asciz "\033[2m"
esc_RED:	.asciz "\033[38;5;203m"
esc_GRN:	.asciz "\033[38;5;114m"
esc_YEL:	.asciz "\033[38;5;221m"
esc_GLD:	.asciz "\033[38;5;215m"
esc_BLU:	.asciz "\033[38;5;110m"
esc_MAG:	.asciz "\033[38;5;176m"
esc_CYN:	.asciz "\033[38;5;152m"
esc_GRY:	.asciz "\033[38;5;245m"
esc_DRK:	.asciz "\033[38;5;238m"
esc_WHT:	.asciz "\033[38;5;253m"
esc_BRN:	.asciz "\033[38;5;180m"

	.section __DATA,__const
	.p2align 3
floor_scenes:
	.quad art_dock, lbl_dock, art_boiler, lbl_boiler, art_pantry, lbl_pantry
quiet_lines:
	.quad L_dock_scale, L_dock_book, L_dock_cart
	.quad L_boiler_steam, L_boiler_mug, L_boiler_bell
	.quad L_pantry_jar, L_pantry_spoon, L_pantry_tin
colortab:		// control byte -> ANSI sequence (0 = not a colour token)
	.quad 0
	.quad esc_R
	.quad esc_B
	.quad esc_DIM
	.quad esc_RED
	.quad esc_GRN
	.quad esc_YEL
	.quad esc_GLD
	.quad 0
	.quad 0
	.quad 0
	.quad 0
	.quad 0
	.quad 0
	.quad esc_BLU
	.quad esc_MAG
	.quad esc_CYN
	.quad esc_GRY
	.quad esc_DRK
	.quad esc_WHT
	.quad esc_BRN
monsters:		// article, rest, hp, atk, gold, flavor, art, trait
	.quad Ls0, Ls1, 8, 2, 6, Ls2, art_sleepy_goblin, 0
	.quad Ls0, Ls3, 12, 3, 9, Ls4, art_skeleton, 3
	.quad Ls0, Ls5, 6, 2, 4, Ls6, art_giant_rat, 1
	.quad Ls0, Ls7, 16, 4, 18, Ls8, art_cursed_barista, 4
	.quad Ls0, Ls9, 10, 2, 7, Ls10, art_slime, 5
	.quad Ls0, Ls11, 9, 4, 11, Ls12, art_shadow_imp, 2
	.quad Ls13, Ls14, 22, 5, 25, Ls15, art_espresso_golem, 3
	.quad Ls0, Lm0, 14, 3, 12, Lm1, art_french_press, 3
	.quad Ls0, Lm2, 7, 3, 8, Lm3, art_weevils, 2
	.quad Ls0, Lm4, 18, 4, 20, Lm5, art_lich, 1
	.quad Ls13, Lm6, 20, 4, 30, Lm7, art_manager, 6
prefixes:		// name, hp, atk, gold
	.quad Ls16, 2, 2, 3
	.quad Ls17, -3, 0, -2
	.quad Ls18, 4, 1, 5
	.quad Ls19, 1, 2, 8
	.quad Ls20, 0, 3, -1
	.quad Ls21, -2, -1, 0
	.quad Ls22, 3, 1, 2
	.quad Ls23, 2, 0, 10
	.quad Ls24, 1, 2, 3
	.quad Ls25, 0, 0, 2
	.quad Ls26, 1, 1, 6
suffixes:		// name, hp, atk, gold
	.quad Ls27, 5, 1, 8
	.quad Ls28, 4, 1, 5
	.quad Ls29, -3, -1, -3
	.quad Ls30, 0, 0, -2
	.quad Ls31, 3, 2, 6
	.quad Ls32, 2, 2, 4
	.quad Ls33, 3, 1, 10
	.quad Ls34, -1, -1, 3
	.quad Ls35, 2, 1, 4
	.quad Ls36, 1, 3, 2
materials:		// name, bonus
	.quad Ls37, 1
	.quad Ls38, 1
	.quad Ls39, 1
	.quad Ls40, 1
	.quad Ls41, 2
	.quad Ls42, 2
	.quad Ls43, 2
	.quad Ls44, 2
	.quad Ls45, 2
	.quad Ls46, 3
	.quad Ls18, 3
weapon_types:		// 
	.quad Ls47
	.quad Ls48
	.quad Ls49
	.quad Ls50
	.quad Ls51
	.quad Ls52
	.quad Ls53
	.quad Ls54
armor_types:		// 
	.quad Ls55
	.quad Ls56
	.quad Ls57
	.quad Ls58
	.quad Ls59
	.quad Ls60
themes:		// 
	.quad Ls61
	.quad Ls62
	.quad Ls63
	.quad Ls64
	.quad Ls65
	.quad Ls31
	.quad Ls66
	.quad Ls67
	.quad Ls68
	.quad Ls69
	.quad Ls70
	.quad Ls71
	.quad Ls35
potion_adj:		// 
	.quad Ls72
	.quad Ls73
	.quad Ls74
	.quad Ls75
	.quad Ls76
	.quad Ls77
	.quad Ls78
	.quad Ls79
	.quad Ls80
	.quad Ls81
	.quad Ls82
	.quad Ls83
specials:		// name, kind (0 gold 1 potion 2 weapon 3 armor), lo, hi
	.quad Ls84, 1, 1, 1
	.quad Ls85, 2, 2, 2
	.quad Ls86, 1, 1, 1
	.quad Ls87, 3, 2, 2
	.quad Ls88, 0, 12, 24
traps:		// message, lo, hi
	.quad Ls89, 3, 6
	.quad Ls90, 2, 5
	.quad Ls91, 4, 7
	.quad Ls92, 2, 4
shrine_lines:		// 
	.quad Ls93
	.quad Ls94
	.quad Ls95
fountain_lines:		// 
	.quad Ls96
	.quad Ls97
	.quad Ls98
	.quad Ls99
riddles:		// question, answer, alternative answer
	.quad Lr0, Lr0a, Lr0b
	.quad Lr1, Lr1a, Lr1b
	.quad Lr2, Lr2a, Lr2a
	.quad Lr3, Lr3a, Lr3a
	.quad Lr4, Lr4a, Lr4b
	.quad Lr5, Lr5a, Lr5a
	.quad Lr6, Lr6a, Lr6b
	.quad Lr7, Lr7a, Lr7a
	.quad Lr8, Lr8a, Lr8a
	.quad Lr9, Lr9a, Lr9a
trait_names:		// indexed by monster trait
	.quad 0, Lt1, Lt2, Lt3, Lt4, Lt5, Lt6
windup_tells:		// same trait order
	.quad tell_plain, tell_venom, tell_evasive, tell_armored
	.quad tell_thief, tell_regen, tell_manager
writeups:		// the manager's write-up lines
	.quad Lw0, Lw1, Lw2, Lw3
class_names:
	.quad Lc0, Lc1, Lc2
room_glyphs:
	.quad glyph_quiet, glyph_foe, glyph_cache, glyph_quiet, glyph_shrine
	.quad glyph_shop, glyph_rest, glyph_rest, glyph_oddity, glyph_oddity
map_key:                                // drawn alongside the map, north at the top
	.quad key_bottom, key_goods, key_risk, key_fog, key_top
floor_decks:                            // room IDs in _handle_room order
	.byte 0, 1,1,1,1, 2,2,2,2,2, 3,3, 4, 5,5, 6,6,6, 7,7, 8, 9    // Loading Dock
	.byte 0, 1,1,1,1,1, 2,2,2, 3,3,3,3, 4,4, 5, 6,6, 7,7, 8, 9   // Boilerworks
	.byte 0, 1,1,1,1,1,1,1, 2,2,2, 3,3, 4,4,4, 5, 6, 7,7, 8, 9   // King's Pantry
crew_aisles:
	.byte 3, 4, 8, 9, 15, 16, 20, 21

	.section __TEXT,__cstring,cstring_literals
glyph_quiet:	.asciz "\003:\001"
glyph_foe:	.asciz "\004x\001"
glyph_cache:	.asciz "\007=\001"
glyph_shrine:	.asciz "\017^\001"
glyph_shop:	.asciz "\007$\001"
glyph_rest:	.asciz "\005+\001"
glyph_oddity:	.asciz "\020*\001"
key_top:	.asciz "\002\005@\001 you       \002\020!\001 crew      \007>\001 exit"
key_fog:	.asciz "\022?\001 unknown   \021·\001 cleared"
key_risk:	.asciz "\003:\001 quiet     \004x\001 foe"
key_goods:	.asciz "\007$\001 shop      \007=\001 cache"
key_bottom:	.asciz "\017^\001 shrine    \020*\001 oddity    \005+\001 rest"
Lr0:	.asciz "The more you take, the more you leave behind. What are they?"
Lr0a:	.asciz "footstep"
Lr0b:	.asciz "step"
Lr1:	.asciz "I am ground, tamped and pulled, but never pushed. What am I?"
Lr1a:	.asciz "espresso"
Lr1b:	.asciz "coffee"
Lr2:	.asciz "What has a neck and a cap, but no head?"
Lr2a:	.asciz "bottle"
Lr3:	.asciz "What gets wetter the more it dries?"
Lr3a:	.asciz "towel"
Lr4:	.asciz "I have keys but open no locks. What am I?"
Lr4a:	.asciz "piano"
Lr4b:	.asciz "keyboard"
Lr5:	.asciz "What has to be broken before you can use it?"
Lr5a:	.asciz "egg"
Lr6:	.asciz "I have a spout, a handle and a temper. What am I?"
Lr6a:	.asciz "kettle"
Lr6b:	.asciz "teapot"
Lr7:	.asciz "What can you catch but not throw?"
Lr7a:	.asciz "cold"
Lr8:	.asciz "The more of me there is, the less you see. What am I?"
Lr8a:	.asciz "dark"
Lr9:	.asciz "What has hands but cannot clap?"
Lr9a:	.asciz "clock"
Lt1:	.asciz "Venomous · a bite can poison you for 2 HP per turn."
Lt2:	.asciz "Evasive · dodges one hit in four. A riposte always lands."
Lt3:	.asciz "Armored · absorbs 2 damage per hit, down to a minimum of 1."
Lt4:	.asciz "Light-fingered · steals gold on contact. Win to get it back."
Lt5:	.asciz "Regenerating · heals up to 2 HP before each swing."
Lt6:	.asciz "Managerial · blocks the exit. Each write-up costs 1 ATK this fight."
tell_plain:	.asciz "It rocks back on its heels."
tell_venom:	.asciz "A bead of venom falls to the tiles."
tell_evasive:	.asciz "For half a breath, it holds perfectly still."
tell_armored:	.asciz "Something heavy scrapes across the tile."
tell_thief:	.asciz "One hand points behind you. Watch the other."
tell_regen:	.asciz "It draws itself up to twice its height."
tell_manager:	.asciz "The manager uncaps a red pen."
Lm6:	.asciz "regional manager"
Lm7:	.asciz "'Got a minute? Per my last email...'"
Lw0:	.asciz "'Per my last email.'"
Lw1:	.asciz "'Let's take this offline.'"
Lw2:	.asciz "'This is going in your file.'"
Lw3:	.asciz "'I'm not mad, just disappointed.'"
Lc0:	.asciz "Knight"
Lc1:	.asciz "Barista"
Lc2:	.asciz "Rogue"
Lm0:	.asciz "haunted french press"
Lm1:	.asciz "It plunges menacingly."
Lm2:	.asciz "bean weevil swarm"
Lm3:	.asciz "A thousand tiny mandibles. One opinion."
Lm4:	.asciz "latte-art lich"
Lm5:	.asciz "Its foam is shaped like your face."
Ls0:	.asciz "a"
Ls1:	.asciz "sleepy goblin"
Ls2:	.asciz "It's clutching a tiny mug. Steam rises from it."
Ls3:	.asciz "moss-covered skeleton"
Ls4:	.asciz "It rattles politely before attacking."
Ls5:	.asciz "giant rat"
Ls6:	.asciz "Its eyes glint with caffeinated rage."
Ls7:	.asciz "cursed barista"
Ls8:	.asciz "'Oat milk?' it hisses. You answer wrong."
Ls9:	.asciz "slime"
Ls10:	.asciz "It absorbs your sarcasm and grows."
Ls11:	.asciz "shadow imp"
Ls12:	.asciz "It flickers like a bad terminal."
Ls13:	.asciz "the"
Ls14:	.asciz "King's espresso golem"
Ls15:	.asciz "Pressurized. Loud. Furious."
Ls16:	.asciz "blazing"
Ls17:	.asciz "tiny"
Ls18:	.asciz "ancient"
Ls19:	.asciz "cursed"
Ls20:	.asciz "rabid"
Ls21:	.asciz "decaf"
Ls22:	.asciz "twin"
Ls23:	.asciz "crystal"
Ls24:	.asciz "phantom"
Ls25:	.asciz "tweedy"
Ls26:	.asciz "artisanal"
Ls27:	.asciz "of the depths"
Ls28:	.asciz "the elder"
Ls29:	.asciz "the apprentice"
Ls30:	.asciz "the unwashed"
Ls31:	.asciz "of midnight"
Ls32:	.asciz "the caffeinated"
Ls33:	.asciz "of the bean court"
Ls34:	.asciz "the lonely"
Ls35:	.asciz "of the second pour"
Ls36:	.asciz "the over-extracted"
Ls37:	.asciz "rusted"
Ls38:	.asciz "splintered"
Ls39:	.asciz "plain"
Ls40:	.asciz "copper"
Ls41:	.asciz "bone"
Ls42:	.asciz "ironwood"
Ls43:	.asciz "polished"
Ls44:	.asciz "gilded"
Ls45:	.asciz "jagged"
Ls46:	.asciz "obsidian"
Ls47:	.asciz "sword"
Ls48:	.asciz "dagger"
Ls49:	.asciz "mace"
Ls50:	.asciz "hammer"
Ls51:	.asciz "axe"
Ls52:	.asciz "spear"
Ls53:	.asciz "cleaver"
Ls54:	.asciz "rapier"
Ls55:	.asciz "shield"
Ls56:	.asciz "buckler"
Ls57:	.asciz "gauntlet"
Ls58:	.asciz "cuirass"
Ls59:	.asciz "helm"
Ls60:	.asciz "vambrace"
Ls61:	.asciz "of the King"
Ls62:	.asciz "of beans"
Ls63:	.asciz "of dawn"
Ls64:	.asciz "of the deep"
Ls65:	.asciz "of regret"
Ls66:	.asciz "of the brewmaster"
Ls67:	.asciz "of caffeine"
Ls68:	.asciz "of the lost cup"
Ls69:	.asciz "of the steeping"
Ls70:	.asciz "of the crooked oak"
Ls71:	.asciz "of small mercies"
Ls72:	.asciz "fizzing"
Ls73:	.asciz "tepid"
Ls74:	.asciz "glowing"
Ls75:	.asciz "steaming"
Ls76:	.asciz "inky"
Ls77:	.asciz "syrupy"
Ls78:	.asciz "bitter"
Ls79:	.asciz "velvet"
Ls80:	.asciz "milky"
Ls81:	.asciz "shimmering"
Ls82:	.asciz "frothy"
Ls83:	.asciz "gritty"
Ls84:	.asciz "a stale croissant"
Ls85:	.asciz "the King's chipped mug"
Ls86:	.asciz "a half-finished journal"
Ls87:	.asciz "the brewmaster's apron"
Ls88:	.asciz "a moth-eaten map fragment"
Ls89:	.asciz "Spikes shoot from the floor!"
Ls90:	.asciz "A dart whistles past — mostly past."
Ls91:	.asciz "The floor crumbles. You catch yourself, but it stings."
Ls92:	.asciz "A swarm of paper cuts. Yes, paper. Yes, cuts."
Ls93:	.asciz "A statue of a cat holding a mug. You leave an offering."
Ls94:	.asciz "Cold stone hums. Something inside you reorganizes."
Ls95:	.asciz "The shrine smells faintly of cinnamon."
Ls96:	.asciz "A stone fountain bubbles in the corner. The water tastes like a perfect cortado."
Ls97:	.asciz "Steam rises from the fountain's icy water. You drink. You feel seen."
Ls98:	.asciz "A frog winks at you from inside the fountain basin. You drink anyway."
Ls99:	.asciz "A copper mug rests on the fountain rim. You fill it, drink, set it back."
