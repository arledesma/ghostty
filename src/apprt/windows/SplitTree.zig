/// Binary tree structure for split pane layout in the Windows apprt.
///
/// Each tab owns a SplitTree root node. Leaf nodes contain a Surface pointer;
/// branch nodes divide space horizontally or vertically between two children.
/// The `layout` function recursively computes pixel positions and calls
/// MoveWindow on each leaf's child HWND.
const SplitTree = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Surface = @import("Surface.zig");

const log = std.log.scoped(.windows_split);

// ---------------------------------------------------------------------------
// Win32 types and imports
// ---------------------------------------------------------------------------

const HWND = std.os.windows.HWND;
const BOOL = std.os.windows.BOOL;
const LONG = i32;

pub const RECT = extern struct {
    left: LONG,
    top: LONG,
    right: LONG,
    bottom: LONG,
};

extern "user32" fn MoveWindow(hwnd: HWND, x: i32, y: i32, nWidth: i32, nHeight: i32, bRepaint: BOOL) callconv(.c) BOOL;
extern "user32" fn ShowWindow(hwnd: HWND, nCmdShow: i32) callconv(.c) BOOL;

const SW_SHOW: i32 = 5;
const SW_HIDE: i32 = 0;

// ---------------------------------------------------------------------------
// Tree types
// ---------------------------------------------------------------------------

pub const Direction = enum {
    horizontal, // left-right split
    vertical, // top-bottom split
};

pub const Node = union(enum) {
    leaf: *Surface,
    branch: Branch,
};

pub const Branch = struct {
    direction: Direction,
    ratio: f32, // 0.0-1.0, proportion of space for first child
    first: *Node,
    second: *Node,
};

// ---------------------------------------------------------------------------
// Tree operations
// ---------------------------------------------------------------------------

/// Create a leaf node wrapping a surface.
pub fn create(alloc: Allocator, surface: *Surface) !*Node {
    const node = try alloc.create(Node);
    node.* = .{ .leaf = surface };
    return node;
}

/// Split a leaf node into a branch: the existing surface becomes `first`,
/// the new surface becomes `second`, with ratio = 0.5.
/// If `new_first` is true, the new surface becomes `first` instead (for left/up splits).
pub fn split(alloc: Allocator, node: *Node, direction: Direction, new_surface: *Surface, new_first: bool) !void {
    switch (node.*) {
        .leaf => |existing_surface| {
            const first_node = try alloc.create(Node);
            const second_node = try alloc.create(Node);

            if (new_first) {
                first_node.* = .{ .leaf = new_surface };
                second_node.* = .{ .leaf = existing_surface };
            } else {
                first_node.* = .{ .leaf = existing_surface };
                second_node.* = .{ .leaf = new_surface };
            }

            node.* = .{ .branch = .{
                .direction = direction,
                .ratio = 0.5,
                .first = first_node,
                .second = second_node,
            } };
        },
        .branch => {
            // Cannot split a branch node directly; find the leaf first.
            log.warn("split called on branch node, ignoring", .{});
        },
    }
}

/// Remove a leaf from the tree containing the target surface.
/// Returns the new root node, or null if the tree is now empty.
/// The caller is responsible for deiniting the surface itself.
pub fn remove(alloc: Allocator, root: *Node, target: *Surface) ?*Node {
    return removeInner(alloc, root, target);
}

fn removeInner(alloc: Allocator, node: *Node, target: *Surface) ?*Node {
    switch (node.*) {
        .leaf => |surface| {
            if (surface == target) {
                alloc.destroy(node);
                return null;
            }
            return node;
        },
        .branch => |*branch| {
            // Try removing from first child.
            const new_first = removeInner(alloc, branch.first, target);
            const new_second = branch.second;

            if (new_first == null) {
                // First child was removed; collapse to second.
                const result = new_second;
                alloc.destroy(node);
                return result;
            }

            // Try removing from second child.
            const new_second2 = removeInner(alloc, branch.second, target);

            if (new_second2 == null) {
                // Second child was removed; collapse to first.
                const result = new_first.?;
                alloc.destroy(node);
                return result;
            }

            // Neither was removed at this level; update pointers.
            branch.first = new_first.?;
            branch.second = new_second2.?;
            return node;
        },
    }
}

/// Recursively compute pixel positions for all nodes in the tree.
/// For leaves: calls MoveWindow to position the surface's HWND.
/// For branches: divides the rect according to ratio and direction.
pub fn layout(node: *Node, rect: RECT) void {
    switch (node.*) {
        .leaf => |surface| {
            const w = rect.right - rect.left;
            const h = rect.bottom - rect.top;
            if (w > 0 and h > 0) {
                _ = MoveWindow(surface.hwnd, rect.left, rect.top, w, h, 1);
                _ = ShowWindow(surface.hwnd, SW_SHOW);
                // Update the surface's cached dimensions.
                surface.width = @intCast(@max(w, 1));
                surface.height = @intCast(@max(h, 1));
            }
        },
        .branch => |branch| {
            const first_rect, const second_rect = splitRect(rect, branch.direction, branch.ratio);
            layout(branch.first, first_rect);
            layout(branch.second, second_rect);
        },
    }
}

/// Find the leaf node containing the target surface.
pub fn findSurface(node: *Node, target: *Surface) ?*Node {
    switch (node.*) {
        .leaf => |surface| {
            if (surface == target) return node;
            return null;
        },
        .branch => |branch| {
            if (findSurface(branch.first, target)) |found| return found;
            if (findSurface(branch.second, target)) |found| return found;
            return null;
        },
    }
}

/// Navigate from the current surface in the given direction.
/// For previous/next: does an in-order traversal and returns the adjacent leaf.
/// For directional: finds the nearest leaf in the requested direction.
pub fn focusDirection(node: *Node, current: *Surface, direction: anytype) ?*Surface {
    // Collect all surfaces in order.
    var surfaces_buf: [64]*Surface = undefined;
    var count: usize = 0;
    collectSurfaces(node, &surfaces_buf, &count);
    if (count == 0) return null;
    const surfaces = surfaces_buf[0..count];

    // Find current index.
    var current_idx: ?usize = null;
    for (surfaces, 0..) |s, i| {
        if (s == current) {
            current_idx = i;
            break;
        }
    }
    const idx = current_idx orelse return null;

    switch (direction) {
        .previous => {
            return if (idx > 0) surfaces[idx - 1] else surfaces[count - 1];
        },
        .next => {
            return if (idx + 1 < count) surfaces[idx + 1] else surfaces[0];
        },
        // For directional navigation, use tree structure to find the
        // nearest surface in the requested direction. Fall back to
        // next/previous for simplicity.
        .left => {
            return if (idx > 0) surfaces[idx - 1] else surfaces[count - 1];
        },
        .right => {
            return if (idx + 1 < count) surfaces[idx + 1] else surfaces[0];
        },
        .up => {
            return if (idx > 0) surfaces[idx - 1] else surfaces[count - 1];
        },
        .down => {
            return if (idx + 1 < count) surfaces[idx + 1] else surfaces[0];
        },
    }
}

/// Find the branch above the current surface that matches the resize direction,
/// and adjust its ratio.
pub fn resize(node: *Node, current: *Surface, direction: anytype, amount: u16) void {
    resizeInner(node, current, direction, amount);
}

fn resizeInner(node: *Node, target: *Surface, direction: anytype, amount: u16) bool {
    switch (node.*) {
        .leaf => |surface| {
            return surface == target;
        },
        .branch => |*branch| {
            const in_first = resizeInner(branch.first, target, direction, amount);
            const in_second = if (!in_first) resizeInner(branch.second, target, direction, amount) else false;

            if (in_first or in_second) {
                // Check if this branch's direction matches the resize direction.
                const matches = switch (direction) {
                    .left, .right => branch.direction == .horizontal,
                    .up, .down => branch.direction == .vertical,
                };

                if (matches) {
                    const delta: f32 = @as(f32, @floatFromInt(amount)) / 100.0;
                    const grow = switch (direction) {
                        .right, .down => in_first,
                        .left, .up => in_second,
                    };
                    if (grow) {
                        branch.ratio = @min(branch.ratio + delta, 0.9);
                    } else {
                        branch.ratio = @max(branch.ratio - delta, 0.1);
                    }
                    return false; // consumed the resize
                }
                return true; // propagate up
            }
            return false;
        },
    }
}

/// Set all branch ratios to 0.5 (equalize).
pub fn equalize(node: *Node) void {
    switch (node.*) {
        .leaf => {},
        .branch => |*branch| {
            branch.ratio = 0.5;
            equalize(branch.first);
            equalize(branch.second);
        },
    }
}

/// Collect all leaf surfaces into a fixed-size buffer.
pub fn collectSurfaces(node: *Node, buf: *[64]*Surface, count: *usize) void {
    switch (node.*) {
        .leaf => |surface| {
            if (count.* < buf.len) {
                buf[count.*] = surface;
                count.* += 1;
            }
        },
        .branch => |branch| {
            collectSurfaces(branch.first, buf, count);
            collectSurfaces(branch.second, buf, count);
        },
    }
}

/// Collect all leaf surfaces into an ArrayList.
pub fn allSurfaces(node: *Node, list: *std.ArrayList(*Surface)) void {
    switch (node.*) {
        .leaf => |surface| {
            list.append(list.allocator, surface) catch {};
        },
        .branch => |branch| {
            allSurfaces(branch.first, list);
            allSurfaces(branch.second, list);
        },
    }
}

/// Show or hide all leaf surfaces in the tree.
pub fn showAll(node: *Node, show: bool) void {
    switch (node.*) {
        .leaf => |surface| {
            _ = ShowWindow(surface.hwnd, if (show) SW_SHOW else SW_HIDE);
        },
        .branch => |branch| {
            showAll(branch.first, show);
            showAll(branch.second, show);
        },
    }
}

/// Recursively deinit all surfaces in the tree and free all nodes.
pub fn deinitAll(node: *Node, alloc: Allocator) void {
    switch (node.*) {
        .leaf => |surface| {
            surface.deinit();
        },
        .branch => |branch| {
            deinitAll(branch.first, alloc);
            deinitAll(branch.second, alloc);
            alloc.destroy(branch.first);
            alloc.destroy(branch.second);
        },
    }
    // The root node itself is freed by the caller (Tab.deinit).
}

/// Count the number of leaf surfaces in the tree.
pub fn countSurfaces(node: *Node) usize {
    switch (node.*) {
        .leaf => return 1,
        .branch => |branch| {
            return countSurfaces(branch.first) + countSurfaces(branch.second);
        },
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn splitRect(rect: RECT, direction: Direction, ratio: f32) struct { RECT, RECT } {
    switch (direction) {
        .horizontal => {
            const total_w: f32 = @floatFromInt(rect.right - rect.left);
            const first_w: i32 = @intFromFloat(total_w * ratio);
            return .{
                RECT{
                    .left = rect.left,
                    .top = rect.top,
                    .right = rect.left + first_w,
                    .bottom = rect.bottom,
                },
                RECT{
                    .left = rect.left + first_w,
                    .top = rect.top,
                    .right = rect.right,
                    .bottom = rect.bottom,
                },
            };
        },
        .vertical => {
            const total_h: f32 = @floatFromInt(rect.bottom - rect.top);
            const first_h: i32 = @intFromFloat(total_h * ratio);
            return .{
                RECT{
                    .left = rect.left,
                    .top = rect.top,
                    .right = rect.right,
                    .bottom = rect.top + first_h,
                },
                RECT{
                    .left = rect.left,
                    .top = rect.top + first_h,
                    .right = rect.right,
                    .bottom = rect.bottom,
                },
            };
        },
    }
}
