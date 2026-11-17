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
1:	bl	_flush
	STR	x0, "clear"
	bl	_system
	LEAVE

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

// rnd(x0 n) -> uniform in [0, n)
_rnd:
	stp	x29, x30, [sp, -16]!
	mov	x29, sp
	bl	_arc4random_uniform
	mov	w0, w0
	ldp	x29, x30, [sp], 16
	ret

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
	mov	x0, 7
	bl	_rnd
	LA	x19, monsters
	mov	x8, 56
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

// Fills t_name, t_kind (0 gold, 1 potion, 2 weapon, 3 armor), t_lo, t_hi.
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
4:	mov	x0, 12                          // potion
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

// ---------- panels ----------

_show_art:
	ENTER
	mov	x1, x0
	SAY	"%s"
	LEAVE

// map_cell(x0 x, x1 y)
_map_cell:
	ENTER
	LDQ	x8, p_x
	LDQ	x9, p_y
	cmp	x0, x8
	b.ne	1f
	cmp	x1, x9
	b.ne	1f
	SAY	"\002\005@\001"
	LEAVE
1:	mov	x8, 5
	madd	x19, x1, x8, x0
	LA	x8, visited
	ldrb	w20, [x8, x19]
	cmp	x19, 24
	b.ne	2f
	cbz	w20, 3f
	SAY	"\002\007>\001"
	LEAVE
2:	cbz	w20, 3f
	SAY	"\021·\001"
	LEAVE
3:	SAY	"\022?\001"
	LEAVE

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
	bl	_map_cell
	SAY	" "
	add	x19, x19, 1
	cmp	x19, 5
	b.lo	2b
	SAY	"\022│\001\n"
	subs	x20, x20, 1
	b.ge	1b
	SAY	"\022╰"
	STR	x0, "─"
	mov	x1, 16
	bl	_rep
	SAY	"╯\001\n"
	SAY	"   \002\005@\001 you   \021·\001 visited   \022?\001 unknown   \002\007>\001 exit\n"
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
2:	mov	x8, 47
	sub	x19, x8, x19
	LA	x1, p_name
	SAY	"\022╭─ %s "
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
	STR	x0, " \023ATK\001 %-3ld \023ARM\001 %-3ld \007Gold\001 %-5ld \017Potions\001 %ld"
	bl	_pline
	LDQ	x1, p_lvl
	LDQ	x2, p_xp
	mov	x8, 20
	mul	x3, x1, x8
	LDQ	x4, depth
	STR	x0, " \023Lv\001  %-3ld \023XP\001 %ld/%ld   \020Floor\001 %ld/3"
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
	bl	_divider
	SAY	"  \023You\001    "
	LDQ	x0, p_hp
	LDQ	x1, p_max
	mov	x2, 14
	bl	_hp_bar
	LDQ	x1, p_hp
	LDQ	x2, p_max
	SAY	"  \023%ld/%ld\001\n"
	SAY	"  \004Foe\001    "
	LDQ	x0, foe_hp
	LDQ	x1, m_hp
	mov	x2, 14
	bl	_hp_bar
	LDQ	x1, foe_hp
	LDQ	x2, m_hp
	SAY	"  \023%ld/%ld\001\n"
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

// foe_hit -> damage the current monster deals to the player
_foe_hit:
	ENTER
	LDQ	x8, m_atk
	sub	x0, x8, 1
	add	x1, x8, 1
	LDQ	x9, boss
	cbz	x9, 1f
	ADDQ	boss_turns, 1                   // every third King turn: the espresso
	LDQ	x9, boss_turns
	mov	x10, 3
	udiv	x11, x9, x10
	msub	x11, x11, x10, x9
	cbnz	x11, 1f
	LOG	"\017  ☕ The King hurls a scalding espresso!\001"
	LDQ	x8, m_atk
	add	x0, x8, 3
	add	x1, x8, 5
1:	bl	_randint
	bl	_hurt
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
	STQ	xzr, boss_turns
	STQ	xzr, boss_healed
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

// combat -> x0: 0 won, 1 fled, 2 dead
_combat:
	ENTER
	LDQ	x8, m_hp
	STQ	x8, foe_hp
	STQ	xzr, log_n
	LDQ	x2, m_flavor
	LOG	"\003\023  %s\001"
1:	LDQ	x8, foe_hp
	cmp	x8, 0
	b.le	90f
	LDQ	x8, p_hp
	cmp	x8, 0
	b.le	90f
	bl	_render_combat
	STR	x0, "  \003[a]ttack  [h]eavy  [p]otion  [r]un >\001 "
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
	cmp	w19, 'p'
	b.eq	20f
	cmp	w19, 'r'
	b.eq	30f
	b	40f
10:	LDQ	x8, p_atk                       // attack
	sub	x0, x8, 1
	add	x1, x8, 2
	bl	_randint
	mov	x20, x0
	LDQ	x8, foe_hp
	sub	x8, x8, x20
	STQ	x8, foe_hp
	LA	x2, m_name
	mov	x3, x20
	LOG	"\005  → You hit %s for %ld.\001"
11:	LDQ	x8, foe_hp
	cmp	x8, 0
	b.le	90f
	bl	_boss_check
	bl	_foe_hit
	mov	x3, x0
	LA	x2, m_name
	LOG	"\004  ← %s hits you for %ld.\001"
	b	1b
15:	mov	x0, 2                           // heavy: double damage or a miss
	bl	_rnd
	cbnz	x0, 16f
	LDQ	x8, p_atk
	sub	x0, x8, 1
	add	x1, x8, 2
	bl	_randint
	lsl	x20, x0, 1
	LDQ	x8, foe_hp
	sub	x8, x8, x20
	STQ	x8, foe_hp
	mov	x2, x20
	LOG	"\002\005  ⇒ A crushing blow! %ld damage.\001"
	b	11b
16:	LOG	"\003  You swing wide and miss.\001"
	b	11b
20:	LDQ	x8, p_pot                       // potion
	cmp	x8, 0
	b.gt	21f
	LOG	"\003  No potions. Pockets full of lint.\001"
	b	1b
21:	ADDQ	p_pot, -1
	mov	x0, 10
	bl	_heal
	mov	x2, x0
	LOG	"\005  ✚ You drink. +%ld HP.\001"
	bl	_foe_hit
	mov	x3, x0
	LA	x2, m_name
	LOG	"\004  ← %s clips you for %ld mid-sip.\001"
	b	1b
30:	LDQ	x8, boss                        // run
	cbz	x8, 32f
	LOG	"\004  The King's gaze pins you in place.\001"
	b	31f
32:	mov	x0, 2
	bl	_rnd
	cbnz	x0, 31f
	mov	x0, 1
	LEAVE
31:	bl	_foe_hit
	mov	x3, x0
	LA	x2, m_name
	LOG	"\004  ← You stumble. %s clips you for %ld.\001"
	b	1b
40:	LOG	"\003  That's not a thing you can do.\001"
	b	1b
90:	LDQ	x8, p_hp
	cmp	x8, 0
	mov	x0, 0
	mov	x1, 2
	csel	x0, x1, x0, le
	LEAVE

// ---------- rooms ----------

_merchant:
	ENTER
	LDQ	x8, p_x
	LDQ	x9, p_y
	mov	x10, 5
	madd	x19, x9, x10, x8
	LA	x20, rooms
	mov	x21, 0                          // a message from the last choice?
1:	LA	x0, art_merchant
	LA	x1, lbl_merchant
	bl	_render_top
	SAY	"\023  A hooded figure unfolds a tiny table.\001\n\003  'Buying or browsing?'\001\n\n"
	cbz	x21, 2f
	LA	x1, msgbuf
	SAY	"%s\n"
2:	bl	_render_bottom
	SAY	"\n  \023[1]\001 Potion           \0075g\001\n  \023[2]\001 Sharpen weapon  \00712g\001  (+1 ATK)\n  \023[3]\001 Reinforce armor \00712g\001  (+1 ARM)\n  \023[4]\001 Mystery box     \00710g\001\n  \023[5]\001 Leave\n"
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
	b	1b
133:	ADDQ	p_max, 2
	ADDQ	p_hp, 2
	MSG	"\005  Max HP +2.\001"
	b	1b
14:	cmp	w8, '5'
	b.eq	50f
40:	MSG	"\003  Not enough gold, or not a real choice.\001"
	b	1b
50:	strb	wzr, [x20, x19]
	LA	x0, art_empty
	LA	x1, lbl_empty
	bl	_render_top
	SAY	"\003  The figure refolds the table and is gone.\001\n"
	bl	_render_bottom
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

	LA	x0, art_empty                   // empty
	LA	x1, lbl_empty
	bl	_render_top
	SAY	"\003  The room is empty. Dust. A faint smell of beans.\001\n"
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
33:	LA	x1, m_name
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
43:	ADDQ	p_arm, x22
	mov	x2, x22
	MSG	"\005  Armor +%ld.\001"
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
65:	strb	wzr, [x20, x19]
	mov	x0, 0
	LEAVE

70:	bl	_merchant                       // merchant
	mov	x0, 0
	LEAVE

80:	mov	x0, 4                           // fountain
	bl	_rnd
	LA	x8, fountain_lines
	ldr	x21, [x8, x0, lsl 3]
	mov	x0, 8
	bl	_heal
	mov	x22, x0
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

85:	LA	x0, art_campfire                // campfire
	LA	x1, lbl_campfire
	bl	_render_top
	SAY	"\006  Embers glow in a ring of stones. Someone left a kettle.\001\n"
	bl	_render_bottom
	strb	wzr, [x20, x19]
	STR	x0, "\n  \003Rest here? [y/N] >\001 "
	mov	x1, 1
	bl	_readline
	ldrb	w8, [x0]
	cmp	w8, 'y'
	b.ne	87f
	ldrb	w8, [x0, 1]
	cbnz	w8, 87f
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

90:	mov	x0, 5                           // riddle
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

// ---------- main loop ----------

// gen_dungeon: a fresh 5x5 floor, index = y*5 + x
_gen_dungeon:
	ENTER
	LA	x19, rooms
	LA	x20, visited
	mov	x21, 0
2:	mov	x8, 0
	cbz	x21, 3f                         // entrance and exit are empty
	cmp	x21, 24
	b.eq	3f
	mov	x0, 100
	bl	_rnd
	LA	x9, room_cum
	mov	x8, 0
4:	ldrb	w10, [x9, x8]
	cmp	x0, x10
	b.lo	3f
	add	x8, x8, 1
	b	4b
3:	strb	w8, [x19, x21]
	strb	wzr, [x20, x21]
	add	x21, x21, 1
	cmp	x21, 25
	b.lo	2b
	mov	w8, 1
	strb	w8, [x20]
	LEAVE

_play:
	ENTER
	bl	_clear
	LA	x0, art_banner
	bl	_show_art
	SAY	"\n"
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

	mov	x8, 1
	STQ	x8, p_lvl
	STQ	x8, depth
	STQ	xzr, p_xp
	STQ	xzr, boss
	bl	_gen_dungeon

	LA	x0, art_start
	LA	x1, lbl_start
	bl	_render_top
	LA	x1, p_name
	SAY	"\023  Welcome, %s.\001\n\003  The King hoards every bean north of the river.\001\n\003  Three floors down, he waits. Find the > on each floor.\001\n"
	bl	_render_bottom

10:	LDQ	x8, p_hp
	cmp	x8, 0
	b.le	20f
	STR	x0, "\n  \003[w/a/s/d] move  [i] info  [q] quit >\001 "
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
15:	SAY	"\003  Try w/a/s/d.\001\n"
	b	10b
16:	SAY	"\003  A wall. Rude.\001\n"
	b	10b
17:	SAY	"\003  Find > in the far corner of each floor. @ is you. · visited. ? unknown.\001\n"
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
	LEAVE

30:	LDQ	x8, depth
	cmp	x8, 3
	b.ge	35f
	bl	_clear                          // stairs down
	LA	x0, art_stairs
	bl	_show_art
	SAY	"\n"
	bl	_divider
	STR	x0, "\007  A spiral stair winds down into the dark.\001\n"
	bl	_slow
	ADDQ	depth, 1
	LDQ	x1, depth
	STR	x0, "\003  Floor %ld. The air smells of burnt sugar.\001\n"
	bl	_slow
	bl	_divider
	STR	x0, "\n  \003[enter] descend >\001 "
	mov	x1, 0
	bl	_readline
	bl	_gen_dungeon
	STQ	xzr, p_x
	STQ	xzr, p_y
	LA	x0, art_start
	LA	x1, lbl_start
	bl	_render_top
	LDQ	x1, depth
	SAY	"\023  Floor %ld of 3.\001\n\003  The monsters down here have had more coffee.\001\n"
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
	STR	x0, "\n  \003[enter] fight >\001 "
	mov	x1, 0
	bl	_readline
	bl	_setup_boss
	bl	_combat
	cmp	x0, 2
	b.eq	20b

	bl	_clear                          // victory
	LA	x0, art_exit
	bl	_show_art
	SAY	"\n"
	bl	_divider
	STR	x0, "\007  The King slumps into his sacks. Behind the throne: a kitchen.\001\n"
	bl	_slow
	STR	x0, "\007  On the counter: the King's last bean.\001\n"
	bl	_slow
	STR	x0, "\002\007  You take it.\001\n"
	bl	_slow
	bl	_divider
	SAY	"\n"
	LDQ	x1, p_turns
	LDQ	x2, p_lvl
	LDQ	x3, p_gold
	LDQ	x4, p_hp
	SAY	"\002\005  ★ VICTORY in %ld turns at level %ld, with %ld gold and %ld HP.\001\n\n"
99:	LEAVE

	.globl _main
_main:
	ENTER
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
boss_turns:	.quad 0
boss_healed:	.quad 0

.zerofill __DATA,__bss,p_name,256,3
.zerofill __DATA,__bss,m_name,256,3
.zerofill __DATA,__bss,t_name,256,3
.zerofill __DATA,__bss,upbuf,256,3
.zerofill __DATA,__bss,msgbuf,256,3
.zerofill __DATA,__bss,tmpa,256,3
.zerofill __DATA,__bss,tmpb,256,3
.zerofill __DATA,__bss,tmpc,256,3
.zerofill __DATA,__bss,logbuf,1024,3
.zerofill __DATA,__bss,rooms,32,3
.zerofill __DATA,__bss,visited,32,3
.zerofill __DATA,__bss,inbuf,512,3
.zerofill __DATA,__bss,slowbuf,1024,3
.zerofill __DATA,__bss,fmtbuf,4096,3
.zerofill __DATA,__bss,outbuf,65536,3

// ---------- data ----------

	.section __TEXT,__cstring,cstring_literals
art_banner:	.ascii "\007"
	.ascii "   ____                  _      ___   __    _   _            _\n"
	.ascii "  / ___|_ __ _   _ _ __ | |_   / _ \\ / _|  | |_| |__   ___  | | _____ _ __\n"
	.ascii " | |   | '__| | | | '_ \\| __| | | | | |_   | __| '_ \\ / _ \\ | |/ / _ \\ '__|\n"
	.ascii " | |___| |  | |_| | |_) | |_  | |_| |  _|  | |_| | | |  __/ |   <  __/ |\n"
	.ascii "  \\____|_|   \\__, | .__/ \\__|  \\___/|_|     \\__|_| |_|\\___|_|_|\\_\\___|_|\n"
	.ascii "             |___/|_|\n"
	.ascii "              C a f f e i n a t e d   K i n g\n"
	.asciz "\001"
art_start:	.ascii "\023"
	.ascii "            _____\n"
	.ascii "           /     \\\n"
	.ascii "          |  . .  |     a stone arch yawns ahead.\n"
	.ascii "           \\_____/      mountain air at your back.\n"
	.ascii "            |   |       the dark hums.\n"
	.asciz "\001"
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
lbl_start:	.asciz "\002\023  @  CRYPT ENTRANCE\001\n"
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
monsters:		// article, rest, hp, atk, gold, flavor, art
	.quad Ls0, Ls1, 8, 2, 6, Ls2, art_sleepy_goblin
	.quad Ls0, Ls3, 12, 3, 9, Ls4, art_skeleton
	.quad Ls0, Ls5, 6, 2, 4, Ls6, art_giant_rat
	.quad Ls0, Ls7, 16, 4, 18, Ls8, art_cursed_barista
	.quad Ls0, Ls9, 10, 2, 7, Ls10, art_slime
	.quad Ls0, Ls11, 9, 4, 11, Ls12, art_shadow_imp
	.quad Ls13, Ls14, 22, 5, 25, Ls15, art_espresso_golem
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
room_cum:		// cumulative weights: empty monster treasure trap shrine merchant fountain campfire riddle
	.byte 8, 38, 54, 65, 72, 79, 90, 95, 100

	.section __TEXT,__cstring,cstring_literals
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
