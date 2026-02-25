//! DirectWrite-based font discovery for Windows.
//!
//! This module implements font discovery using the DirectWrite COM API,
//! following the same interface pattern as the Fontconfig and CoreText
//! discovery backends. DirectWrite discovers system fonts and returns
//! file paths that Freetype can use for rasterization (via FT_New_Face).
//!
//! COM call chain:
//!   DWriteCreateFactory -> IDWriteFactory
//!     -> GetSystemFontCollection -> IDWriteFontCollection
//!       -> FindFamilyName / GetFontFamily -> IDWriteFontFamily
//!         -> GetFont -> IDWriteFont
//!           -> CreateFontFace -> IDWriteFontFace
//!             -> GetFiles -> IDWriteFontFile
//!               -> GetReferenceKey + GetLoader
//!                 -> IDWriteLocalFontFileLoader::GetFilePathFromKey
//!                   -> file path string -> Freetype FT_New_Face()

const std = @import("std");
const Allocator = std.mem.Allocator;
const font = @import("../main.zig");
const DeferredFace = font.DeferredFace;
const Descriptor = font.discovery.Descriptor;
const Variation = font.face.Variation;

const log = std.log.scoped(.discovery);

/// HRESULT type for COM calls.
const HRESULT = i32;

/// BOOL type for COM calls.
const BOOL = i32;

/// GUID for COM interface identification.
const GUID = extern struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,
};

/// FILETIME structure.
const FILETIME = extern struct {
    low: u32,
    high: u32,
};

/// DWRITE_FONT_WEIGHT enum values we care about.
const DWRITE_FONT_WEIGHT = enum(u32) {
    thin = 100,
    extra_light = 200,
    light = 300,
    semi_light = 350,
    normal = 400,
    medium = 500,
    semi_bold = 600,
    bold = 700,
    extra_bold = 800,
    black = 900,
    _,
};

/// DWRITE_FONT_STYLE enum.
const DWRITE_FONT_STYLE = enum(u32) {
    normal = 0,
    oblique = 1,
    italic = 2,
};

/// DWRITE_FONT_STRETCH enum.
const DWRITE_FONT_STRETCH = enum(u32) {
    undefined = 0,
    ultra_condensed = 1,
    extra_condensed = 2,
    condensed = 3,
    semi_condensed = 4,
    normal = 5,
    semi_expanded = 6,
    expanded = 7,
    extra_expanded = 8,
    ultra_expanded = 9,
};

/// DWRITE_FACTORY_TYPE enum.
const DWRITE_FACTORY_TYPE = enum(u32) {
    shared = 0,
    isolated = 1,
};

/// DWRITE_FONT_SIMULATIONS enum.
const DWRITE_FONT_SIMULATIONS = packed struct(u32) {
    bold: bool = false,
    oblique: bool = false,
    _padding: u30 = 0,
};

/// IDWriteFactory COM interface vtable.
const IDWriteFactory = extern struct {
    vtable: *const VTable,

    const VTable = extern struct {
        // IUnknown (3 methods)
        QueryInterface: *const fn (*const IDWriteFactory, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*const IDWriteFactory) callconv(.c) u32,
        Release: *const fn (*const IDWriteFactory) callconv(.c) u32,
        // IDWriteFactory methods (we only need GetSystemFontCollection)
        GetSystemFontCollection: *const fn (
            *const IDWriteFactory,
            *?*IDWriteFontCollection,
            BOOL, // checkForUpdates
        ) callconv(.c) HRESULT,
        // Remaining methods are unused stubs for vtable offset correctness
        CreateCustomFontCollection: *const fn (*const IDWriteFactory, *anyopaque, *const anyopaque, u32, *?*anyopaque) callconv(.c) HRESULT,
        RegisterFontCollectionLoader: *const fn (*const IDWriteFactory, *anyopaque) callconv(.c) HRESULT,
        UnregisterFontCollectionLoader: *const fn (*const IDWriteFactory, *anyopaque) callconv(.c) HRESULT,
        CreateFontFileReference: *const fn (*const IDWriteFactory, [*:0]const u16, ?*const FILETIME, *?*IDWriteFontFile) callconv(.c) HRESULT,
    };

    fn release(self: *const IDWriteFactory) void {
        _ = self.vtable.Release(self);
    }
};

/// IDWriteFontCollection COM interface vtable.
const IDWriteFontCollection = extern struct {
    vtable: *const VTable,

    const VTable = extern struct {
        // IUnknown (3 methods)
        QueryInterface: *const fn (*const IDWriteFontCollection, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*const IDWriteFontCollection) callconv(.c) u32,
        Release: *const fn (*const IDWriteFontCollection) callconv(.c) u32,
        // IDWriteFontCollection methods
        GetFontFamilyCount: *const fn (*const IDWriteFontCollection) callconv(.c) u32,
        GetFontFamily: *const fn (*const IDWriteFontCollection, u32, *?*IDWriteFontFamily) callconv(.c) HRESULT,
        FindFamilyName: *const fn (*const IDWriteFontCollection, [*:0]const u16, *u32, *BOOL) callconv(.c) HRESULT,
        GetFontFromFontFace: *const fn (*const IDWriteFontCollection, *anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    };

    fn release(self: *const IDWriteFontCollection) void {
        _ = self.vtable.Release(self);
    }
};

/// IDWriteFontFamily COM interface vtable.
/// Inherits from IDWriteFontList which inherits from IUnknown.
const IDWriteFontFamily = extern struct {
    vtable: *const VTable,

    const VTable = extern struct {
        // IUnknown (3 methods)
        QueryInterface: *const fn (*const IDWriteFontFamily, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*const IDWriteFontFamily) callconv(.c) u32,
        Release: *const fn (*const IDWriteFontFamily) callconv(.c) u32,
        // IDWriteFontList methods (2 methods)
        GetFontCollection: *const fn (*const IDWriteFontFamily, *?*anyopaque) callconv(.c) HRESULT,
        GetFontCount: *const fn (*const IDWriteFontFamily) callconv(.c) u32,
        GetFont: *const fn (*const IDWriteFontFamily, u32, *?*IDWriteFont) callconv(.c) HRESULT,
        // IDWriteFontFamily methods
        GetFamilyNames: *const fn (*const IDWriteFontFamily, *?*IDWriteLocalizedStrings) callconv(.c) HRESULT,
    };

    fn release(self: *const IDWriteFontFamily) void {
        _ = self.vtable.Release(self);
    }
};

/// IDWriteFont COM interface vtable.
const IDWriteFont = extern struct {
    vtable: *const VTable,

    const VTable = extern struct {
        // IUnknown (3 methods)
        QueryInterface: *const fn (*const IDWriteFont, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*const IDWriteFont) callconv(.c) u32,
        Release: *const fn (*const IDWriteFont) callconv(.c) u32,
        // IDWriteFont methods
        GetFontFamily: *const fn (*const IDWriteFont, *?*anyopaque) callconv(.c) HRESULT,
        GetWeight: *const fn (*const IDWriteFont) callconv(.c) DWRITE_FONT_WEIGHT,
        GetStretch: *const fn (*const IDWriteFont) callconv(.c) DWRITE_FONT_STRETCH,
        GetStyle: *const fn (*const IDWriteFont) callconv(.c) DWRITE_FONT_STYLE,
        IsSymbolFont: *const fn (*const IDWriteFont) callconv(.c) BOOL,
        GetFaceNames: *const fn (*const IDWriteFont, *?*anyopaque) callconv(.c) HRESULT,
        GetInformationalStrings: *const fn (*const IDWriteFont, u32, *?*anyopaque, *BOOL) callconv(.c) HRESULT,
        GetSimulations: *const fn (*const IDWriteFont) callconv(.c) DWRITE_FONT_SIMULATIONS,
        GetMetrics: *const fn (*const IDWriteFont, *anyopaque) callconv(.c) void,
        HasCharacter: *const fn (*const IDWriteFont, u32, *BOOL) callconv(.c) HRESULT,
        CreateFontFace: *const fn (*const IDWriteFont, *?*IDWriteFontFace) callconv(.c) HRESULT,
    };

    fn release(self: *const IDWriteFont) void {
        _ = self.vtable.Release(self);
    }
};

/// IDWriteFontFace COM interface vtable.
const IDWriteFontFace = extern struct {
    vtable: *const VTable,

    const VTable = extern struct {
        // IUnknown (3 methods)
        QueryInterface: *const fn (*const IDWriteFontFace, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*const IDWriteFontFace) callconv(.c) u32,
        Release: *const fn (*const IDWriteFontFace) callconv(.c) u32,
        // IDWriteFontFace methods
        GetType: *const fn (*const IDWriteFontFace) callconv(.c) u32,
        GetFiles: *const fn (*const IDWriteFontFace, *u32, ?[*]?*IDWriteFontFile) callconv(.c) HRESULT,
        GetIndex: *const fn (*const IDWriteFontFace) callconv(.c) u32,
        GetSimulations: *const fn (*const IDWriteFontFace) callconv(.c) DWRITE_FONT_SIMULATIONS,
        IsSymbolFont: *const fn (*const IDWriteFontFace) callconv(.c) BOOL,
    };

    fn release(self: *const IDWriteFontFace) void {
        _ = self.vtable.Release(self);
    }
};

/// IDWriteFontFile COM interface vtable.
const IDWriteFontFile = extern struct {
    vtable: *const VTable,

    const VTable = extern struct {
        // IUnknown (3 methods)
        QueryInterface: *const fn (*const IDWriteFontFile, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*const IDWriteFontFile) callconv(.c) u32,
        Release: *const fn (*const IDWriteFontFile) callconv(.c) u32,
        // IDWriteFontFile methods
        GetReferenceKey: *const fn (*const IDWriteFontFile, *?*const anyopaque, *u32) callconv(.c) HRESULT,
        GetLoader: *const fn (*const IDWriteFontFile, *?*IDWriteFontFileLoader) callconv(.c) HRESULT,
    };

    fn release(self: *const IDWriteFontFile) void {
        _ = self.vtable.Release(self);
    }
};

/// IDWriteFontFileLoader COM interface vtable.
const IDWriteFontFileLoader = extern struct {
    vtable: *const VTable,

    const VTable = extern struct {
        // IUnknown (3 methods)
        QueryInterface: *const fn (*const IDWriteFontFileLoader, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*const IDWriteFontFileLoader) callconv(.c) u32,
        Release: *const fn (*const IDWriteFontFileLoader) callconv(.c) u32,
        // IDWriteFontFileLoader methods
        CreateStreamFromKey: *const fn (*const IDWriteFontFileLoader, *const anyopaque, u32, *?*anyopaque) callconv(.c) HRESULT,
    };

    fn release(self: *const IDWriteFontFileLoader) void {
        _ = self.vtable.Release(self);
    }
};

/// IDWriteLocalFontFileLoader COM interface vtable.
/// Inherits from IDWriteFontFileLoader.
const IDWriteLocalFontFileLoader = extern struct {
    vtable: *const VTable,

    const VTable = extern struct {
        // IUnknown (3 methods)
        QueryInterface: *const fn (*const IDWriteLocalFontFileLoader, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*const IDWriteLocalFontFileLoader) callconv(.c) u32,
        Release: *const fn (*const IDWriteLocalFontFileLoader) callconv(.c) u32,
        // IDWriteFontFileLoader methods (1 method)
        CreateStreamFromKey: *const fn (*const IDWriteLocalFontFileLoader, *const anyopaque, u32, *?*anyopaque) callconv(.c) HRESULT,
        // IDWriteLocalFontFileLoader methods
        GetFilePathLengthFromKey: *const fn (*const IDWriteLocalFontFileLoader, *const anyopaque, u32, *u32) callconv(.c) HRESULT,
        GetFilePathFromKey: *const fn (*const IDWriteLocalFontFileLoader, *const anyopaque, u32, [*]u16, u32) callconv(.c) HRESULT,
        GetLastWriteTimeFromKey: *const fn (*const IDWriteLocalFontFileLoader, *const anyopaque, u32, *FILETIME) callconv(.c) HRESULT,
    };

    fn release(self: *const IDWriteLocalFontFileLoader) void {
        _ = self.vtable.Release(self);
    }
};

/// IDWriteLocalizedStrings COM interface vtable.
const IDWriteLocalizedStrings = extern struct {
    vtable: *const VTable,

    const VTable = extern struct {
        // IUnknown (3 methods)
        QueryInterface: *const fn (*const IDWriteLocalizedStrings, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
        AddRef: *const fn (*const IDWriteLocalizedStrings) callconv(.c) u32,
        Release: *const fn (*const IDWriteLocalizedStrings) callconv(.c) u32,
        // IDWriteLocalizedStrings methods
        GetCount: *const fn (*const IDWriteLocalizedStrings) callconv(.c) u32,
        FindLocaleName: *const fn (*const IDWriteLocalizedStrings, [*:0]const u16, *u32, *BOOL) callconv(.c) HRESULT,
        GetLocaleNameLength: *const fn (*const IDWriteLocalizedStrings, u32, *u32) callconv(.c) HRESULT,
        GetLocaleName: *const fn (*const IDWriteLocalizedStrings, u32, [*]u16, u32) callconv(.c) HRESULT,
        GetStringLength: *const fn (*const IDWriteLocalizedStrings, u32, *u32) callconv(.c) HRESULT,
        GetString: *const fn (*const IDWriteLocalizedStrings, u32, [*]u16, u32) callconv(.c) HRESULT,
    };

    fn release(self: *const IDWriteLocalizedStrings) void {
        _ = self.vtable.Release(self);
    }
};

// IID for IDWriteFactory: b859ee5a-d838-4b5b-a2e8-1adc7d93db48
const IID_IDWriteFactory = GUID{
    .data1 = 0xb859ee5a,
    .data2 = 0xd838,
    .data3 = 0x4b5b,
    .data4 = .{ 0xa2, 0xe8, 0x1a, 0xdc, 0x7d, 0x93, 0xdb, 0x48 },
};

// IID for IDWriteLocalFontFileLoader: b2d9f3ec-c9fe-4a11-a2ec-d86208f7c0a2
const IID_IDWriteLocalFontFileLoader = GUID{
    .data1 = 0xb2d9f3ec,
    .data2 = 0xc9fe,
    .data3 = 0x4a11,
    .data4 = .{ 0xa2, 0xec, 0xd8, 0x62, 0x08, 0xf7, 0xc0, 0xa2 },
};

/// DWriteCreateFactory import from dwrite.dll.
extern "dwrite" fn DWriteCreateFactory(
    factoryType: DWRITE_FACTORY_TYPE,
    iid: *const GUID,
    factory: *?*IDWriteFactory,
) callconv(.c) HRESULT;

/// Check if HRESULT indicates success.
inline fn succeeded(hr: HRESULT) bool {
    return hr >= 0;
}

/// DirectWrite font discovery implementation.
///
/// Follows the same interface pattern as Fontconfig and CoreText in
/// discovery.zig: init/deinit for lifecycle, discover() returns an
/// iterator of DeferredFace results.
pub const DirectWrite = struct {
    factory: *IDWriteFactory,
    collection: *IDWriteFontCollection,

    pub fn init() DirectWrite {
        // Create the DirectWrite factory (shared, process-wide)
        var factory: ?*IDWriteFactory = null;
        const hr_factory = DWriteCreateFactory(
            .shared,
            &IID_IDWriteFactory,
            &factory,
        );
        if (!succeeded(hr_factory) or factory == null) {
            @panic("Failed to create DirectWrite factory");
        }

        // Get the system font collection
        var collection: ?*IDWriteFontCollection = null;
        const hr_collection = factory.?.vtable.GetSystemFontCollection(
            factory.?,
            &collection,
            0, // don't check for updates
        );
        if (!succeeded(hr_collection) or collection == null) {
            factory.?.release();
            @panic("Failed to get system font collection");
        }

        return .{
            .factory = factory.?,
            .collection = collection.?,
        };
    }

    pub fn deinit(self: *DirectWrite) void {
        self.collection.release();
        self.factory.release();
    }

    /// Discover fonts matching the given descriptor. Returns an iterator
    /// that yields DeferredFace values suitable for lazy Freetype loading.
    pub fn discover(
        self: *const DirectWrite,
        alloc: Allocator,
        desc: Descriptor,
    ) !DiscoverIterator {
        // If we have a family name, do a targeted lookup
        if (desc.family) |family| {
            // Convert UTF-8 family name to UTF-16 for DirectWrite
            var buf_u16: [256]u16 = undefined;
            const family_u16 = utf8ToUtf16(&buf_u16, family) catch {
                return DiscoverIterator.empty(alloc, desc.variations);
            };

            // Look up the family by name
            var family_index: u32 = 0;
            var exists: BOOL = 0;
            const hr = self.collection.vtable.FindFamilyName(
                self.collection,
                family_u16,
                &family_index,
                &exists,
            );
            if (!succeeded(hr) or exists == 0) {
                return DiscoverIterator.empty(alloc, desc.variations);
            }

            // Get the font family
            var dw_family: ?*IDWriteFontFamily = null;
            const hr_fam = self.collection.vtable.GetFontFamily(
                self.collection,
                family_index,
                &dw_family,
            );
            if (!succeeded(hr_fam) or dw_family == null) {
                return DiscoverIterator.empty(alloc, desc.variations);
            }
            defer dw_family.?.release();

            // Enumerate fonts in this family, collecting those that match
            // the descriptor's weight/style criteria
            return try collectMatchingFonts(alloc, dw_family.?, desc);
        }

        // No family specified -- return empty iterator
        // (font discovery without a family name is not meaningful on Windows)
        return DiscoverIterator.empty(alloc, desc.variations);
    }

    pub fn discoverFallback(
        self: *const DirectWrite,
        alloc: Allocator,
        collection: *font.Collection,
        desc: Descriptor,
    ) !DiscoverIterator {
        _ = collection;
        return try self.discover(alloc, desc);
    }

    /// Collect fonts from a family that match the descriptor criteria.
    fn collectMatchingFonts(
        alloc: Allocator,
        family: *IDWriteFontFamily,
        desc: Descriptor,
    ) !DiscoverIterator {
        const font_count = family.vtable.GetFontCount(family);
        if (font_count == 0) {
            return DiscoverIterator.empty(alloc, desc.variations);
        }

        // Collect all font file paths from this family
        var paths: std.ArrayListUnmanaged(FontPath) = .{};
        errdefer {
            for (paths.items) |*p| p.deinit(alloc);
            paths.deinit(alloc);
        }

        // Target weight and style from descriptor
        const target_weight: DWRITE_FONT_WEIGHT = if (desc.bold) .bold else .normal;
        const target_style: DWRITE_FONT_STYLE = if (desc.italic) .italic else .normal;

        // First pass: try to find exact matches, then fall back to collecting all
        var i: u32 = 0;
        while (i < font_count) : (i += 1) {
            var dw_font: ?*IDWriteFont = null;
            const hr = family.vtable.GetFont(family, i, &dw_font);
            if (!succeeded(hr) or dw_font == null) continue;
            defer dw_font.?.release();

            // Check weight and style match
            const weight = dw_font.?.vtable.GetWeight(dw_font.?);
            const style = dw_font.?.vtable.GetStyle(dw_font.?);

            const weight_match = weightMatches(weight, target_weight, desc.bold);
            const style_match = (style == target_style);

            if (!weight_match or !style_match) continue;

            // Extract the file path from this font
            if (extractFontPath(alloc, dw_font.?)) |font_path| {
                try paths.append(alloc, font_path);
            } else |_| {
                // Skip fonts we can't extract paths from
                continue;
            }
        }

        // If no exact matches, collect all fonts in the family
        if (paths.items.len == 0) {
            i = 0;
            while (i < font_count) : (i += 1) {
                var dw_font: ?*IDWriteFont = null;
                const hr = family.vtable.GetFont(family, i, &dw_font);
                if (!succeeded(hr) or dw_font == null) continue;
                defer dw_font.?.release();

                if (extractFontPath(alloc, dw_font.?)) |font_path| {
                    try paths.append(alloc, font_path);
                } else |_| {
                    continue;
                }
            }
        }

        const owned_slice = try paths.toOwnedSlice(alloc);

        return .{
            .alloc = alloc,
            .paths = owned_slice,
            .variations = desc.variations,
            .i = 0,
        };
    }

    /// Determine if a font weight is a reasonable match for the target.
    fn weightMatches(
        actual: DWRITE_FONT_WEIGHT,
        target: DWRITE_FONT_WEIGHT,
        want_bold: bool,
    ) bool {
        const actual_val = @intFromEnum(actual);
        const target_val = @intFromEnum(target);
        if (want_bold) {
            // Accept anything semi-bold or heavier
            return actual_val >= 600;
        } else {
            // Accept anything within a reasonable range of normal (300-500)
            const diff = if (actual_val > target_val)
                actual_val - target_val
            else
                target_val - actual_val;
            return diff <= 100;
        }
    }

    /// Stored font path result from DirectWrite discovery.
    const FontPath = struct {
        /// Null-terminated UTF-8 file path for Freetype.
        path: [:0]const u8,
        /// Face index within the font file.
        face_index: u32,

        fn deinit(self: *FontPath, alloc: Allocator) void {
            alloc.free(self.path);
            self.* = undefined;
        }
    };

    /// Extract the font file path from a DirectWrite font object.
    /// Returns the file path as a null-terminated UTF-8 string.
    fn extractFontPath(alloc: Allocator, dw_font: *IDWriteFont) !FontPath {
        // Create font face
        var font_face: ?*IDWriteFontFace = null;
        const hr_face = dw_font.vtable.CreateFontFace(dw_font, &font_face);
        if (!succeeded(hr_face) or font_face == null) return error.CreateFontFaceFailed;
        defer font_face.?.release();

        // Get the face index
        const face_index = font_face.?.vtable.GetIndex(font_face.?);

        // Get font files (we only need the first one)
        var file_count: u32 = 1;
        var font_file: ?*IDWriteFontFile = null;
        const hr_files = font_face.?.vtable.GetFiles(
            font_face.?,
            &file_count,
            @ptrCast(&font_file),
        );
        if (!succeeded(hr_files) or font_file == null) return error.GetFilesFailed;
        defer font_file.?.release();

        // Get the reference key
        var ref_key: ?*const anyopaque = null;
        var ref_key_size: u32 = 0;
        const hr_key = font_file.?.vtable.GetReferenceKey(
            font_file.?,
            &ref_key,
            &ref_key_size,
        );
        if (!succeeded(hr_key) or ref_key == null) return error.GetReferenceKeyFailed;

        // Get the loader
        var loader: ?*IDWriteFontFileLoader = null;
        const hr_loader = font_file.?.vtable.GetLoader(font_file.?, &loader);
        if (!succeeded(hr_loader) or loader == null) return error.GetLoaderFailed;
        defer loader.?.release();

        // QueryInterface for IDWriteLocalFontFileLoader
        var local_loader: ?*IDWriteLocalFontFileLoader = null;
        const hr_qi = loader.?.vtable.QueryInterface(
            loader.?,
            &IID_IDWriteLocalFontFileLoader,
            @ptrCast(&local_loader),
        );
        if (!succeeded(hr_qi) or local_loader == null) return error.NotLocalFont;
        defer local_loader.?.release();

        // Get the file path length
        var path_length: u32 = 0;
        const hr_len = local_loader.?.vtable.GetFilePathLengthFromKey(
            local_loader.?,
            ref_key.?,
            ref_key_size,
            &path_length,
        );
        if (!succeeded(hr_len)) return error.GetFilePathLengthFailed;

        // Get the file path (UTF-16)
        const buf_size = path_length + 1; // +1 for null terminator
        const path_buf = try alloc.alloc(u16, buf_size);
        defer alloc.free(path_buf);
        const hr_path = local_loader.?.vtable.GetFilePathFromKey(
            local_loader.?,
            ref_key.?,
            ref_key_size,
            path_buf.ptr,
            buf_size,
        );
        if (!succeeded(hr_path)) return error.GetFilePathFailed;

        // Convert UTF-16 path to UTF-8
        const path_utf8 = try utf16ToUtf8Alloc(alloc, path_buf[0..path_length]);

        return .{
            .path = path_utf8,
            .face_index = face_index,
        };
    }

    /// Iterator that yields DeferredFace values from discovered font paths.
    pub const DiscoverIterator = struct {
        alloc: Allocator,
        paths: []FontPath,
        variations: []const Variation,
        i: usize,

        fn empty(alloc: Allocator, variations: []const Variation) DiscoverIterator {
            return .{
                .alloc = alloc,
                .paths = &.{},
                .variations = variations,
                .i = 0,
            };
        }

        pub fn deinit(self: *DiscoverIterator) void {
            for (self.paths) |*p| p.deinit(self.alloc);
            if (self.paths.len > 0) self.alloc.free(self.paths);
            self.* = undefined;
        }

        pub fn next(self: *DiscoverIterator) !?DeferredFace {
            if (self.i >= self.paths.len) return null;
            defer self.i += 1;

            const font_path = self.paths[self.i];

            return DeferredFace{
                .dw = .{
                    .path = font_path.path,
                    .face_index = font_path.face_index,
                    .variations = self.variations,
                },
            };
        }
    };
};

/// Convert a UTF-8 slice to a null-terminated UTF-16LE buffer.
/// Returns a sentinel-terminated pointer into the provided buffer.
fn utf8ToUtf16(buf: []u16, utf8: []const u8) ![:0]const u16 {
    var i: usize = 0;
    var utf8_i: usize = 0;
    while (utf8_i < utf8.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(utf8[utf8_i]) catch return error.InvalidUtf8;
        if (utf8_i + cp_len > utf8.len) return error.InvalidUtf8;
        const cp = std.unicode.utf8Decode(utf8[utf8_i..][0..cp_len]) catch return error.InvalidUtf8;
        utf8_i += cp_len;

        if (cp < 0x10000) {
            if (i >= buf.len - 1) return error.BufferTooSmall;
            buf[i] = @intCast(cp);
            i += 1;
        } else {
            // Surrogate pair
            if (i + 1 >= buf.len - 1) return error.BufferTooSmall;
            const adjusted = cp - 0x10000;
            buf[i] = @intCast(0xD800 + (adjusted >> 10));
            buf[i + 1] = @intCast(0xDC00 + (adjusted & 0x3FF));
            i += 2;
        }
    }
    if (i >= buf.len) return error.BufferTooSmall;
    buf[i] = 0;
    return buf[0..i :0];
}

/// Convert a UTF-16LE slice to a null-terminated UTF-8 string (heap-allocated).
fn utf16ToUtf8Alloc(alloc: Allocator, utf16: []const u16) ![:0]const u8 {
    // Calculate required UTF-8 length
    var utf8_len: usize = 0;
    var j: usize = 0;
    while (j < utf16.len) {
        const unit = utf16[j];
        if (unit == 0) break; // stop at null
        if (unit < 0x80) {
            utf8_len += 1;
            j += 1;
        } else if (unit < 0x800) {
            utf8_len += 2;
            j += 1;
        } else if (unit >= 0xD800 and unit <= 0xDBFF) {
            // High surrogate
            utf8_len += 4;
            j += 2;
        } else {
            utf8_len += 3;
            j += 1;
        }
    }

    const buf = try alloc.allocSentinel(u8, utf8_len, 0);
    errdefer alloc.free(buf);

    var out_i: usize = 0;
    j = 0;
    while (j < utf16.len) {
        const unit = utf16[j];
        if (unit == 0) break;

        var cp: u21 = undefined;
        if (unit >= 0xD800 and unit <= 0xDBFF) {
            // Surrogate pair
            if (j + 1 >= utf16.len) return error.InvalidUtf16;
            const low = utf16[j + 1];
            if (low < 0xDC00 or low > 0xDFFF) return error.InvalidUtf16;
            cp = @intCast((@as(u32, unit - 0xD800) << 10) + @as(u32, low - 0xDC00) + 0x10000);
            j += 2;
        } else {
            cp = @intCast(unit);
            j += 1;
        }

        const len = std.unicode.utf8CodepointSequenceLength(cp) catch return error.InvalidCodepoint;
        if (out_i + len > utf8_len) return error.BufferTooSmall;
        _ = std.unicode.utf8Encode(cp, buf[out_i..][0..4]) catch return error.InvalidCodepoint;
        out_i += len;
    }

    return buf;
}
