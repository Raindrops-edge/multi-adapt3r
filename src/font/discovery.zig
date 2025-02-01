const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const fontconfig = @import("fontconfig");
const macos = @import("macos");
const options = @import("main.zig").options;
const DeferredFace = @import("main.zig").DeferredFace;
const Variation = @import("main.zig").face.Variation;

const log = std.log.scoped(.discovery);

/// Discover implementation for the compile options.
pub const Discover = switch (options.backend) {
    .freetype => void, // no discovery
    .fontconfig_freetype => Fontconfig,
    .coretext, .coretext_freetype => CoreText,
    .web_canvas => void, // no discovery
};

/// Descriptor is used to search for fonts. The only required field
/// is "family". The rest are ignored unless they're set to a non-zero
/// value.
pub const Descriptor = struct {
    /// Font family to search for. This can be a fully qualified font
    /// name such as "Fira Code", "monospace", "serif", etc. Memory is
    /// owned by the caller and should be freed when this descriptor
    /// is no longer in use. The discovery structs will never store the
    /// descriptor.
    ///
    /// On systems that use fontconfig (Linux), this can be a full
    /// fontconfig pattern, such as "Fira Code-14:bold".
    family: ?[:0]const u8 = null,

    /// Specific font style to search for. This will filter the style
    /// string the font advertises. The "bold/italic" booleans later in this
    /// struct filter by the style trait the font has, not the string, so
    /// these can be used in conjunction or not.
    style: ?[:0]const u8 = null,

    /// A codepoint that this font must be able to render.
    codepoint: u32 = 0,

    /// Font size in points that the font should support. For conversion
    /// to pixels, we will use 72 DPI for Mac and 96 DPI for everything else.
    /// (If pixel conversion is necessary, i.e. emoji fonts)
    size: u16 = 0,

    /// True if we want to search specifically for a font that supports
    /// specific styles.
    bold: bool = false,
    italic: bool = false,
    monospace: bool = false,

    /// Variation axes to apply to the font. This also impacts searching
    /// for fonts since fonts with the ability to set these variations
    /// will be preferred, but not guaranteed.
    variations: []const Variation = &.{},

    /// Returns a hash code that can be used to uniquely identify this
    /// action.
    pub fn hash(self: Descriptor) u64 {
        const autoHash = std.hash.autoHash;
        var hasher = std.hash.Wyhash.init(0);
        autoHash(&hasher, self.family);
        autoHash(&hasher, self.style);
        autoHash(&hasher, self.codepoint);
        autoHash(&hasher, self.size);
        autoHash(&hasher, self.bold);
        autoHash(&hasher, self.italic);
        autoHash(&hasher, self.monospace);
        autoHash(&hasher, self.variations.len);
        for (self.variations) |variation| {
            autoHash(&hasher, variation.id);

            // This is not correct, but we don't currently depend on the
            // hash value being different based on decimal values of variations.
            autoHash(&hasher, @as(u64, @intFromFloat(variation.value)));
        }

        return hasher.final();
    }

    /// Convert to Fontconfig pattern to use for lookup. The pattern does
    /// not have defaults filled/substituted (Fontconfig thing) so callers
    /// must still do this.
    pub fn toFcPattern(self: Descriptor) *fontconfig.Pattern {
        const pat = fontconfig.Pattern.create();
        if (self.family) |family| {
            assert(pat.add(.family, .{ .string = family }, false));
        }
        if (self.style) |style| {
            assert(pat.add(.style, .{ .string = style }, false));
        }
        if (self.codepoint > 0) {
            const cs = fontconfig.CharSet.create();
            defer cs.destroy();
            assert(cs.addChar(self.codepoint));
            assert(pat.add(.charset, .{ .char_set = cs }, false));
        }
        if (self.size > 0) assert(pat.add(
            .size,
            .{ .integer = self.size },
            false,
        ));
        if (self.bold) assert(pat.add(
            .weight,
            .{ .integer = @intFromEnum(fontconfig.Weight.bold) },
            false,
        ));
        if (self.italic) assert(pat.add(
            .slant,
            .{ .integer = @intFromEnum(fontconfig.Slant.italic) },
            false,
        ));

        return pat;
    }

    /// Convert to Core Text font descriptor to use for lookup or
    /// conversion to a specific font.
    pub fn toCoreTextDescriptor(self: Descriptor) !*macos.text.FontDescriptor {
        const attrs = try macos.foundation.MutableDictionary.create(0);
        defer attrs.release();

        // Family
        if (self.family) |family_bytes| {
            const family = try macos.foundation.String.createWithBytes(family_bytes, .utf8, false);
            defer family.release();
            attrs.setValue(
                macos.text.FontAttribute.family_name.key(),
                family,
            );
        }

        // Style
        if (self.style) |style_bytes| {
            const style = try macos.foundation.String.createWithBytes(style_bytes, .utf8, false);
            defer style.release();
            attrs.setValue(
                macos.text.FontAttribute.style_name.key(),
                style,
            );
        }

        // Codepoint support
        if (self.codepoint > 0) {
            const cs = try macos.foundation.CharacterSet.createWithCharactersInRange(.{
                .location = self.codepoint,
                .length = 1,
            });
            defer cs.release();
            attrs.setValue(
                macos.text.FontAttribute.character_set.key(),
                cs,
            );
        }

        // Set our size attribute if set
        if (self.size > 0) {
            const size32 = @as(i32, @intCast(self.size));
            const size = try macos.foundation.Number.create(
                .sint32,
                &size32,
            );
            defer size.release();
            attrs.setValue(
                macos.text.FontAttribute.size.key(),
                size,
            );
        }

        // Build our traits. If we set any, then we store it in the attributes
        // otherwise we do nothing. We determine this by setting up the packed
        // struct, converting to an int, and checking if it is non-zero.
        const traits: macos.text.FontSymbolicTraits = .{
            .bold = self.bold,
            .italic = self.italic,
            .monospace = self.monospace,
        };
        const traits_cval: u32 = @bitCast(traits);
        if (traits_cval > 0) {
            // Setting traits is a pain. We have to create a nested dictionary
            // of the symbolic traits value, and set that in our attributes.
            const traits_num = try macos.foundation.Number.create(
                .sint32,
                @as(*const i32, @ptrCast(&traits_cval)),
            );
            defer traits_num.release();

            const traits_dict = try macos.foundation.MutableDictionary.create(0);
            defer traits_dict.release();
            traits_dict.setValue(
                macos.text.FontTraitKey.symbolic.key(),
                traits_num,
            );

            attrs.setValue(
                macos.text.FontAttribute.traits.key(),
                traits_dict,
            );
        }

        // Build our descriptor from attrs
        var desc = try macos.text.FontDescriptor.createWithAttributes(@ptrCast(attrs));
        errdefer desc.release();

        // Variations are built by copying the descriptor. I don't know a way
        // to set it on attrs directly.
        for (self.variations) |v| {
            const id = try macos.foundation.Number.create(.int, @ptrCast(&v.id));
            defer id.release();
            const next = try desc.createCopyWithVariation(id, v.value);
            desc.release();
            desc = next;
        }

        return desc;
    }
};

pub const Fontconfig = struct {
    fc_config: *fontconfig.Config,

    pub fn init() Fontconfig {
        // safe to call multiple times and concurrently
        _ = fontconfig.init();
        return .{ .fc_config = fontconfig.initLoadConfigAndFonts() };
    }

    pub fn deinit(self: *Fontconfig) void {
        self.fc_config.destroy();
    }

    /// Discover fonts from a descriptor. This returns an iterator that can
    /// be used to build up the deferred fonts.
    pub fn discover(self: *const Fontconfig, alloc: Allocator, desc: Descriptor) !DiscoverIterator {
        _ = alloc;

        // Build our pattern that we'll search for
        const pat = desc.toFcPattern();
        errdefer pat.destroy();
        assert(self.fc_config.substituteWithPat(pat, .pattern));
        pat.defaultSubstitute();

        // Search
        const res = self.fc_config.fontSort(pat, false, null);
        if (res.result != .match) return error.FontConfigFailed;
        errdefer res.fs.destroy();

        return DiscoverIterator{
            .config = self.fc_config,
            .pattern = pat,
            .set = res.fs,
            .fonts = res.fs.fonts(),
            .variations = desc.variations,
            .i = 0,
        };
    }

    pub const DiscoverIterator = struct {
        config: *fontconfig.Config,
        pattern: *fontconfig.Pattern,
        set: *fontconfig.FontSet,
        fonts: []*fontconfig.Pattern,
        variations: []const Variation,
        i: usize,

        pub fn deinit(self: *DiscoverIterator) void {
            self.set.destroy();
            self.pattern.destroy();
            self.* = undefined;
        }

        pub fn next(self: *DiscoverIterator) fontconfig.Error!?DeferredFace {
            if (self.i >= self.fonts.len) return null;

            // Get the copied pattern from our fontset that has the
            // attributes configured for rendering.
            const font_pattern = try self.config.fontRenderPrepare(
                self.pattern,
                self.fonts[self.i],
            );
            errdefer font_pattern.destroy();

            // Increment after we return
            defer self.i += 1;

            return DeferredFace{
                .fc = .{
                    .pattern = font_pattern,
                    .charset = (try font_pattern.get(.charset, 0)).char_set,
                    .langset = (try font_pattern.get(.lang, 0)).lang_set,
                    .variations = self.variations,
                },
            };
        }
    };
};

pub const CoreText = struct {
    pub fn init() CoreText {
        // Required for the "interface" but does nothing for CoreText.
        return .{};
    }

    pub fn deinit(self: *CoreText) void {
        _ = self;
    }

    /// Discover fonts from a descriptor. This returns an iterator that can
    /// be used to build up the deferred fonts.
    pub fn discover(self: *const CoreText, alloc: Allocator, desc: Descriptor) !DiscoverIterator {
        _ = self;

        // Build our pattern that we'll search for
        const ct_desc = try desc.toCoreTextDescriptor();
        defer ct_desc.release();

        // Our descriptors have to be in an array
        var ct_desc_arr = [_]*const macos.text.FontDescriptor{ct_desc};
        const desc_arr = try macos.foundation.Array.create(macos.text.FontDescriptor, &ct_desc_arr);
        defer desc_arr.release();

        // Build our collection
        const set = try macos.text.FontCollection.createWithFontDescriptors(desc_arr);
        defer set.release();
        const list = set.createMatchingFontDescriptors();
        defer list.release();

        // Sort our descriptors
        const zig_list = try copyMatchingDescriptors(alloc, list);
        errdefer alloc.free(zig_list);
        sortMatchingDescriptors(&desc, zig_list);

        return DiscoverIterator{
            .alloc = alloc,
            .list = zig_list,
            .i = 0,
        };
    }

    fn copyMatchingDescriptors(
        alloc: Allocator,
        list: *macos.foundation.Array,
    ) ![]*macos.text.FontDescriptor {
        var result = try alloc.alloc(*macos.text.FontDescriptor, list.getCount());
        errdefer alloc.free(result);
        for (0..result.len) |i| {
            result[i] = list.getValueAtIndex(macos.text.FontDescriptor, i);

            // We need to retain becauseonce the list is freed it will
            // release all its members.
            result[i].retain();
        }
        return result;
    }

    fn sortMatchingDescriptors(
        desc: *const Descriptor,
        list: []*macos.text.FontDescriptor,
    ) void {
        var desc_mut = desc.*;
        if (desc_mut.style == null) {
            // If there is no explicit style set, we set a preferred
            // based on the style bool attributes.
            //
            // TODO: doesn't handle i18n font names well, we should have
            // another mechanism that uses the weight attribute if it exists.
            // Wait for this to be a real problem.
            desc_mut.style = if (desc_mut.bold and desc_mut.italic)
                "Bold Italic"
            else if (desc_mut.bold)
                "Bold"
            else if (desc_mut.italic)
                "Italic"
            else
                null;
        }

        std.mem.sortUnstable(*macos.text.FontDescriptor, list, &desc_mut, struct {
            fn lessThan(
                desc_inner: *const Descriptor,
                lhs: *macos.text.FontDescriptor,
                rhs: *macos.text.FontDescriptor,
            ) bool {
                const lhs_score = score(desc_inner, lhs);
                const rhs_score = score(desc_inner, rhs);
                // Higher score is "less" (earlier)
                return lhs_score.int() > rhs_score.int();
            }
        }.lessThan);
    }

    /// We represent our sorting score as a packed struct so that we can
    /// compare scores numerically but build scores symbolically.
    const Score = packed struct {
        const Backing = @typeInfo(@This()).Struct.backing_integer.?;

        glyph_count: u16 = 0, // clamped if > intmax
        traits: Traits = .unmatched,
        style: Style = .unmatched,
        monospace: bool = false,
        codepoint: bool = false,

        const Traits = enum(u8) { unmatched = 0, _ };
        const Style = enum(u8) { unmatched = 0, match = 0xFF, _ };

        pub fn int(self: Score) Backing {
            return @bitCast(self);
        }
    };

    fn score(desc: *const Descriptor, ct_desc: *const macos.text.FontDescriptor) Score {
        var score_acc: Score = .{};

        // We always load the font if we can since some things can only be
        // inspected on the font itself.
        const font_: ?*macos.text.Font = macos.text.Font.createWithFontDescriptor(
            ct_desc,
            12,
        ) catch null;
        defer if (font_) |font| font.release();

        // If we have a font, prefer the font with more glyphs.
        if (font_) |font| {
            const Type = @TypeOf(score_acc.glyph_count);
            score_acc.glyph_count = std.math.cast(
                Type,
                font.getGlyphCount(),
            ) orelse std.math.maxInt(Type);
        }

        // If we're searching for a codepoint, prioritize fonts that
        // have that codepoint.
        if (desc.codepoint > 0) codepoint: {
            const font = font_ orelse break :codepoint;

            // Turn UTF-32 into UTF-16 for CT API
            var unichars: [2]u16 = undefined;
            const pair = macos.foundation.stringGetSurrogatePairForLongCharacter(
                desc.codepoint,
                &unichars,
            );
            const len: usize = if (pair) 2 else 1;

            // Get our glyphs
            var glyphs = [2]macos.graphics.Glyph{ 0, 0 };
            score_acc.codepoint = font.getGlyphsForCharacters(unichars[0..len], glyphs[0..len]);
        }

        // Get our symbolic traits for the descriptor so we can compare
        // boolean attributes like bold, monospace, etc.
        const symbolic_traits: macos.text.FontSymbolicTraits = traits: {
            const traits = ct_desc.copyAttribute(.traits);
            defer traits.release();

            const key = macos.text.FontTraitKey.symbolic.key();
            const symbolic = traits.getValue(macos.foundation.Number, key) orelse
                break :traits .{};

            break :traits macos.text.FontSymbolicTraits.init(symbolic);
        };

        score_acc.monospace = symbolic_traits.monospace;

        score_acc.style = style: {
            const style = ct_desc.copyAttribute(.style_name);
            defer style.release();

            // If we have a specific desired style, attempt to search for that.
            if (desc.style) |desired_style| {
                var buf: [128]u8 = undefined;
                const style_str = style.cstring(&buf, .utf8) orelse break :style .unmatched;

                // Matching style string gets highest score
                if (std.mem.eql(u8, desired_style, style_str)) break :style .match;

                // Otherwise the score is based on the length of the style string.
                // Shorter styles are scored higher.
                break :style @enumFromInt(100 -| style_str.len);
            }

            // If we do not, and we have no symbolic traits, then we try
            // to find "regular" (or no style). If we have symbolic traits
            // we do nothing but we can improve scoring by taking that into
            // account, too.
            if (!desc.bold and !desc.italic) {
                var buf: [128]u8 = undefined;
                const style_str = style.cstring(&buf, .utf8) orelse break :style .unmatched;
                if (std.mem.eql(u8, "Regular", style_str)) break :style .match;
            }

            break :style .unmatched;
        };

        score_acc.traits = traits: {
            var count: u8 = 0;
            if (desc.bold == symbolic_traits.bold) count += 1;
            if (desc.italic == symbolic_traits.italic) count += 1;
            break :traits @enumFromInt(count);
        };

        return score_acc;
    }

    pub const DiscoverIterator = struct {
        alloc: Allocator,
        list: []const *macos.text.FontDescriptor,
        i: usize,

        pub fn deinit(self: *DiscoverIterator) void {
            self.alloc.free(self.list);
            self.* = undefined;
        }

        pub fn next(self: *DiscoverIterator) !?DeferredFace {
            if (self.i >= self.list.len) return null;

            // Get our descriptor. We need to remove the character set
            // limitation because we may have used that to filter but we
            // don't want it anymore because it'll restrict the characters
            // available.
            //const desc = self.list.getValueAtIndex(macos.text.FontDescriptor, self.i);
            const desc = desc: {
                const original = self.list[self.i];

                // For some reason simply copying the attributes and recreating
                // the descriptor removes the charset restriction. This is tested.
                const attrs = original.copyAttributes();
                defer attrs.release();
                break :desc try macos.text.FontDescriptor.createWithAttributes(@ptrCast(attrs));
            };
            defer desc.release();

            // Create our font. We need a size to initialize it so we use size
            // 12 but we will alter the size later.
            const font = try macos.text.Font.createWithFontDescriptor(desc, 12);
            errdefer font.release();

            // Increment after we return
            defer self.i += 1;

            return DeferredFace{
                .ct = .{ .font = font },
            };
        }
    };
};

test "descriptor hash" {
    const testing = std.testing;

    var d: Descriptor = .{};
    try testing.expect(d.hash() != 0);
}

test "descriptor hash familiy names" {
    const testing = std.testing;

    var d1: Descriptor = .{ .family = "A" };
    var d2: Descriptor = .{ .family = "B" };
    try testing.expect(d1.hash() != d2.hash());
}

test "fontconfig" {
    if (options.backend != .fontconfig_freetype) return error.SkipZigTest;

    const testing = std.testing;
    const alloc = testing.allocator;

    var fc = Fontconfig.init();
    var it = try fc.discover(alloc, .{ .family = "monospace", .size = 12 });
    defer it.deinit();
}

test "fontconfig codepoint" {
    if (options.backend != .fontconfig_freetype) return error.SkipZigTest;

    const testing = std.testing;
    const alloc = testing.allocator;

    var fc = Fontconfig.init();
    var it = try fc.discover(alloc, .{ .codepoint = 'A', .size = 12 });
    defer it.deinit();

    // The first result should have the codepoint. Later ones may not
    // because fontconfig returns all fonts sorted.
    const face = (try it.next()).?;
    try testing.expect(face.hasCodepoint('A', null));

    // Should have other codepoints too
    try testing.expect(face.hasCodepoint('B', null));
}

test "coretext" {
    if (options.backend != .coretext and options.backend != .coretext_freetype)
        return error.SkipZigTest;

    const testing = std.testing;
    const alloc = testing.allocator;

    var ct = CoreText.init();
    defer ct.deinit();
    var it = try ct.discover(alloc, .{ .family = "Monaco", .size = 12 });
    defer it.deinit();
    var count: usize = 0;
    while (try it.next()) |_| {
        count += 1;
    }
    try testing.expect(count > 0);
}

test "coretext codepoint" {
    if (options.backend != .coretext and options.backend != .coretext_freetype)
        return error.SkipZigTest;

    const testing = std.testing;
    const alloc = testing.allocator;

    var ct = CoreText.init();
    defer ct.deinit();
    var it = try ct.discover(alloc, .{ .codepoint = 'A', .size = 12 });
    defer it.deinit();

    // The first result should have the codepoint. Later ones may not
    // because fontconfig returns all fonts sorted.
    const face = (try it.next()).?;
    try testing.expect(face.hasCodepoint('A', null));

    // Should have other codepoints too
    try testing.expect(face.hasCodepoint('B', null));
}
