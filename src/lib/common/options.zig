const build_options = @import("build_options");
const root = @import("root");

pub const Options = struct {
    showdown: ?bool = null,
    log: ?bool = null,
    chance: ?bool = null,
    advance: ?bool = null,
    ebc: ?bool = null,
    internal: ?bool = null,
};

/// Whether or not Pokémon Showdown compatibility mode is enabled.
pub const showdown = get("showdown", false);
/// Whether or not protocol message logging is enabled.
pub const log = get("log", false);
/// Whether or not update probability tracking is enabled.
pub const chance = get("chance", false);

pub const advance = get("advance", true);
pub const ebc = get("ebc", true);
pub const internal = get("internal", false);

fn get(comptime name: []const u8, default: bool) bool {
    var build_enable: ?bool = null;
    var root_enable: ?bool = null;

    if (@hasDecl(root, "pkmn_options")) {
        root_enable = @field(@as(Options, root.pkmn_options), name);
    }
    if (@hasDecl(build_options, name)) {
        build_enable = @as(?bool, @field(build_options, name));
    }
    if (build_enable != null and root_enable != null) {
        if (build_enable.? != root_enable.?) {
            const r = name ++ " (" ++ (if (root_enable.?) "false" else "true") ++ ")";
            const b = name ++ " (" ++ (if (build_enable.?) "false" else "true") ++ ")";
            @compileError("root decl pkmn_options." ++ r ++ " != build option " ++ b ++ ".");
        }
    }

    return root_enable orelse (build_enable orelse default);
}
