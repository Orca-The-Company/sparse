const std = @import("std");

fn addVendoredDeps(lib: *std.Build.Step.Compile, upstream: *std.Build.Dependency) void {
    lib.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = pcreSrc,
        .flags = &.{
            "-DLINK_SIZE=2",
            "-DNEWLINE=10",
            "-DPOSIX_MALLOC_THRESHOLD=10",
            "-DMATCH_LIMIT_RECURSION=MATCH_LIMIT",
            "-DPARENS_NEST_LIMIT=250",
            "-DMATCH_LIMIT=10000000",
            "-DMAX_NAME_SIZE=32",
            "-DMAX_NAME_COUNT=10000",
        },
    });
    lib.addIncludePath(upstream.path("deps/pcre"));
    lib.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = llhttpSrc,
        .flags = &.{""},
    });
    lib.addIncludePath(upstream.path("deps/llhttp"));
    lib.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = xdiffSrc,
        .flags = &.{""},
    });
    lib.addIncludePath(upstream.path("deps/xdiff"));
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    const root = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .sanitize_c = false,
    });

    const lib = b.addLibrary(.{
        .name = "git2",
        .root_module = root,
        .linkage = .static,
    });
    lib.linkLibC();

    switch (target.result.os.tag) {
        .driverkit, .ios, .macos, .tvos, .visionos, .watchos => {
            const apple_sdk = @import("apple_sdk");
            try apple_sdk.addPaths(b, lib);
            lib.linkFramework("CoreServices");
            try flags.appendSlice(&.{
                "-DGIT_QSORT_BSD=1",
            });
            // lib.root_module.addCMacro("OPENSSL_SYS_MACOSX", "1");
        },
        else => @panic("target platform is not supported"),
    }

    // For dynamic linking, we prefer dynamic linking and to search by
    // mode first. Mode first will search all paths for a dynamic library
    // before falling back to static.
    const dynamic_link_opts: std.Build.Module.LinkSystemLibraryOptions = .{
        .preferred_link_mode = .dynamic,
        .search_strategy = .mode_first,
    };

    // lib.linkSystemLibrary("mbedtls");
    // lib.linkSystemLibrary("llhttp");
    lib.linkSystemLibrary("pthread");

    if (b.systemIntegrationOption("zlib", .{})) {
        lib.linkSystemLibrary2("zlib", dynamic_link_opts);
    } else {
        if (b.lazyDependency(
            "zlib",
            .{ .target = target, .optimize = optimize },
        )) |zlib_dep| {
            lib.linkLibrary(zlib_dep.artifact("z"));
            lib.addIncludePath(b.path(""));
        }
    }

    if (b.lazyDependency("libgit2", .{})) |upstream| {
        lib.addIncludePath(upstream.path("include"));
        lib.addIncludePath(upstream.path("src/libgit2"));
        lib.addIncludePath(upstream.path("src/libgit2/transports"));
        lib.addIncludePath(upstream.path("src/libgit2/streams"));
        lib.addIncludePath(upstream.path("src/util"));
        lib.addIncludePath(b.path("override/include"));
        lib.installHeadersDirectory(upstream.path("include"), "", .{
            .include_extensions = &.{".h"},
        });
        // flags??
        try flags.appendSlice(&.{
            "-DLIBGIT2_NO_FEATURES_H",
            "-DGIT_THREADS=1",
            "-DGIT_THREADS_PTHREADS=1", // TODO: platform specific
            "-DGIT_SHA1_BUILTIN=1",
            "-DGIT_SHA256_BUILTIN=1",
            "-DGIT_COMPRESSION_BUILTIN=1",
            "-DGIT_I18N=1",
            "-DGIT_I18N_ICONV=1",
            "-DGIT_REGEX_PCRE=1",
            "-DGIT_HTTPS=1",
            "-DGIT_HTTPS_SECURETRANSPORT=1",
            "-DGIT_HTTPPARSER_BUILTIN=1",
            "-DGIT_AUTH_NTLM=1",
            "-DGIT_AUTH_NTLM_BUILTIN=1",
            "-DGIT_AUTH_NEGOTIATE=1",
            "-DGIT_AUTH_NEGOTIATE_GSSFRAMEWORK=1",
            "-DGIT_FUTIMENS=1",
            "-DGIT_RAND_GETLOADAVG=1",
            "-DGIT_IO_POLL=1", // TODO: platform specific
            "-DGIT_IO_SELECT=1",
            "-fno-sanitize=all",
        });

        if (target.result.ptrBitWidth() == 64) {
            try flags.append("-DGIT_ARCH_64=1");
        }

        lib.addCSourceFiles(.{
            .root = upstream.path(""),
            .files = srcs,
            .flags = flags.items,
        });
        addVendoredDeps(lib, upstream);
    }
    b.installArtifact(lib);
}

const llhttpSrc: []const []const u8 = &.{
    "./deps/llhttp/api.c",
    "./deps/llhttp/http.c",
    "./deps/llhttp/llhttp.c",
};

const pcreSrc: []const []const u8 = &.{
    "./deps/pcre/pcre_compile.c",
    "./deps/pcre/pcre_xclass.c",
    "./deps/pcre/pcre_ucd.c",
    "./deps/pcre/pcre_byte_order.c",
    "./deps/pcre/pcre_jit_compile.c",
    "./deps/pcre/pcre_get.c",
    "./deps/pcre/pcre_printint.c",
    "./deps/pcre/pcre_exec.c",
    "./deps/pcre/pcre_tables.c",
    "./deps/pcre/pcre_string_utils.c",
    "./deps/pcre/pcreposix.c",
    "./deps/pcre/pcre_version.c",
    "./deps/pcre/pcre_study.c",
    "./deps/pcre/pcre_newline.c",
    "./deps/pcre/pcre_refcount.c",
    "./deps/pcre/pcre_maketables.c",
    "./deps/pcre/pcre_config.c",
    "./deps/pcre/pcre_fullinfo.c",
    "./deps/pcre/pcre_dfa_exec.c",
    "./deps/pcre/pcre_globals.c",
    "./deps/pcre/pcre_ord2utf8.c",
    "./deps/pcre/pcre_valid_utf8.c",
    "./deps/pcre/pcre_chartables.c",
};

const xdiffSrc: []const []const u8 = &.{
    "./deps/xdiff/xhistogram.c",
    "./deps/xdiff/xprepare.c",
    "./deps/xdiff/xpatience.c",
    "./deps/xdiff/xdiffi.c",
    "./deps/xdiff/xmerge.c",
    "./deps/xdiff/xutils.c",
    "./deps/xdiff/xemit.c",
};

const winSrcs: []const []const u8 = &.{
    "src/util/hash/win32.c",
    "src/util/allocators/win32_leakcheck.c",
    "src/util/allocators/win32_leakcheck.h",
    "src/util/win32/precompiled.c",
    "src/util/win32/error.h",
    "src/util/win32/win32-compat.h",
    "src/util/win32/thread.c",
    "src/util/win32/version.h",
    "src/util/win32/process.c",
    "src/util/win32/w32_util.c",
    "src/util/win32/utf-conv.c",
    "src/util/win32/posix_w32.c",
    "src/util/win32/w32_buffer.h",
    "src/util/win32/w32_leakcheck.c",
    "src/util/win32/w32_common.h",
    "src/util/win32/path_w32.h",
    "src/util/win32/dir.c",
    "src/util/win32/thread.h",
    "src/util/win32/error.c",
    "src/util/win32/precompiled.h",
    "src/util/win32/w32_util.h",
    "src/util/win32/map.c",
    "src/util/win32/posix.h",
    "src/util/win32/reparse.h",
    "src/util/win32/msvc-compat.h",
    "src/util/win32/utf-conv.h",
    "src/util/win32/w32_leakcheck.h",
    "src/util/win32/dir.h",
    "src/util/win32/path_w32.c",
    "src/util/win32/w32_buffer.c",
    "src/util/win32/mingw-compat.h",
    "src/util/hash/win32.h",
    "./src/libgit2/transports/winhttp.c",
};

const srcs: []const []const u8 = &.{
    "src/util/cc-compat.h",
    "src/util/futils.h",
    "src/util/varint.h",
    "src/util/zstream.h",
    "src/util/staticstr.h",
    "src/util/thread.c",
    "src/util/wildmatch.c",
    "src/util/fs_path.h",
    "src/util/tsort.c",
    "src/util/runtime.c",
    "src/util/pool.h",
    "src/util/rand.c",
    "src/util/net.h",
    "src/util/util.c",
    "src/util/git2_util.h",
    "src/util/posix.c",
    "src/util/map.h",
    "src/util/hash/rfc6234/sha.h",
    "src/util/hash/rfc6234/sha224-256.c",
    "src/util/hash/mbedtls.c",
    "src/util/hash/builtin.h",
    "src/util/hash/common_crypto.h",
    "src/util/hash/sha.h",
    "src/util/hash/openssl.h",
    "src/util/hash/sha1dc/ubc_check.h",
    "src/util/hash/sha1dc/sha1.c",
    "src/util/hash/sha1dc/sha1.h",
    "src/util/hash/sha1dc/ubc_check.c",
    "src/util/hash/collisiondetect.h",
    "src/util/hash/mbedtls.h",
    "src/util/hash/common_crypto.c",
    "src/util/hash/builtin.c",
    "src/util/hash/openssl.c",
    "src/util/hash/collisiondetect.c",
    "src/util/vector.c",
    "src/util/strlist.c",
    "src/util/ctype_compat.h",
    "src/util/str.c",
    "src/util/filebuf.c",
    "src/util/pqueue.c",
    "src/util/date.h",
    "src/util/assert_safe.h",
    "src/util/errors.h",
    "src/util/hashmap.h",
    "src/util/utf8.c",
    "src/util/regexp.c",
    "src/util/sortedcache.h",
    "src/util/alloc.c",
    "src/util/hash.c",
    "src/util/runtime.h",
    "src/util/wildmatch.h",
    "src/util/hashmap_str.h",
    "src/util/fs_path.c",
    "src/util/unix/process.c",
    "src/util/unix/realpath.c",
    "src/util/unix/map.c",
    "src/util/unix/posix.h",
    "src/util/unix/pthread.h",
    "src/util/thread.h",
    "src/util/futils.c",
    "src/util/zstream.c",
    "src/util/varint.c",
    "src/util/array.h",
    "src/util/posix.h",
    "src/util/util.h",
    "src/util/net.c",
    "src/util/rand.h",
    "src/util/pool.c",
    "src/util/process.h",
    "src/util/allocators/debugalloc.c",
    "src/util/allocators/failalloc.h",
    "src/util/allocators/stdalloc.c",
    "src/util/allocators/debugalloc.h",
    "src/util/allocators/stdalloc.h",
    "src/util/allocators/failalloc.c",
    "src/util/filebuf.h",
    "src/util/pqueue.h",
    "src/util/str.h",
    "src/util/date.c",
    "src/util/bitvec.h",
    "src/util/strnlen.h",
    "src/util/strlist.h",
    "src/util/vector.h",
    "src/util/integer.h",
    "src/util/regexp.h",
    "src/util/hash.h",
    "src/util/sortedcache.c",
    "src/util/alloc.h",
    "src/util/utf8.h",
    "src/util/errors.c",
    "./src/libgit2/commit_graph.c",
    "./src/libgit2/commit_list.c",
    "./src/libgit2/merge_driver.c",
    "./src/libgit2/proxy.c",
    "./src/libgit2/diff.c",
    "./src/libgit2/diff_print.c",
    "./src/libgit2/trace.c",
    "./src/libgit2/fetch.c",
    "./src/libgit2/strarray.c",
    "./src/libgit2/config_list.c",
    "./src/libgit2/trailer.c",
    "./src/libgit2/reflog.c",
    "./src/libgit2/remote.c",
    "./src/libgit2/transport.c",
    "./src/libgit2/revwalk.c",
    "./src/libgit2/object.c",
    "./src/libgit2/config_mem.c",
    "./src/libgit2/patch.c",
    "./src/libgit2/notes.c",
    "./src/libgit2/indexer.c",
    "./src/libgit2/refspec.c",
    "./src/libgit2/ident.c",
    "./src/libgit2/diff_file.c",
    "./src/libgit2/refdb_fs.c",
    "./src/libgit2/push.c",
    "./src/libgit2/tree-cache.c",
    "./src/libgit2/streams/mbedtls.c",
    "./src/libgit2/streams/schannel.c",
    "./src/libgit2/streams/openssl_dynamic.c",
    "./src/libgit2/streams/socket.c",
    "./src/libgit2/streams/openssl_legacy.c",
    "./src/libgit2/streams/tls.c",
    "./src/libgit2/streams/openssl.c",
    "./src/libgit2/streams/registry.c",
    "./src/libgit2/streams/stransport.c",
    "./src/libgit2/revparse.c",
    "./src/libgit2/diff_generate.c",
    "./src/libgit2/diff_stats.c",
    "./src/libgit2/checkout.c",
    "./src/libgit2/config_parse.c",
    "./src/libgit2/transports/ssh.c",
    "./src/libgit2/transports/httpclient.c",
    "./src/libgit2/transports/auth.c",
    "./src/libgit2/transports/credential.c",
    "./src/libgit2/transports/auth_ntlmclient.c",
    "./src/libgit2/transports/local.c",
    "./src/libgit2/transports/httpparser.c",
    "./src/libgit2/transports/credential_helpers.c",
    "./src/libgit2/transports/ssh_exec.c",
    "./src/libgit2/transports/ssh_libssh2.c",
    "./src/libgit2/transports/smart_pkt.c",
    "./src/libgit2/transports/http.c",
    "./src/libgit2/transports/smart_protocol.c",
    "./src/libgit2/transports/auth_gssapi.c",
    "./src/libgit2/transports/git.c",
    "./src/libgit2/transports/smart.c",
    "./src/libgit2/transports/auth_sspi.c",
    "./src/libgit2/apply.c",
    "./src/libgit2/hashsig.c",
    "./src/libgit2/odb_mempack.c",
    "./src/libgit2/config_cache.c",
    "./src/libgit2/patch_generate.c",
    "./src/libgit2/refdb.c",
    "./src/libgit2/commit.c",
    "./src/libgit2/fetchhead.c",
    "./src/libgit2/iterator.c",
    "./src/libgit2/filter.c",
    "./src/libgit2/reset.c",
    "./src/libgit2/refs.c",
    "./src/libgit2/odb_pack.c",
    "./src/libgit2/transaction.c",
    "./src/libgit2/attrcache.c",
    "./src/libgit2/sysdir.c",
    "./src/libgit2/blame.c",
    "./src/libgit2/pack.c",
    "./src/libgit2/oidarray.c",
    "./src/libgit2/attr.c",
    "./src/libgit2/diff_xdiff.c",
    "./src/libgit2/pack-objects.c",
    "./src/libgit2/reader.c",
    "./src/libgit2/grafts.c",
    "./src/libgit2/email.c",
    "./src/libgit2/index.c",
    "./src/libgit2/ignore.c",
    "./src/libgit2/index_map.c",
    "./src/libgit2/signature.c",
    "./src/libgit2/odb_loose.c",
    "./src/libgit2/oid.c",
    "./src/libgit2/repository.c",
    "./src/libgit2/branch.c",
    "./src/libgit2/path.c",
    "./src/libgit2/settings.c",
    "./src/libgit2/config.c",
    "./src/libgit2/annotated_commit.c",
    "./src/libgit2/merge_file.c",
    "./src/libgit2/tag.c",
    "./src/libgit2/odb.c",
    "./src/libgit2/revert.c",
    "./src/libgit2/attr_file.c",
    "./src/libgit2/status.c",
    "./src/libgit2/config_snapshot.c",
    "./src/libgit2/mailmap.c",
    "./src/libgit2/cherrypick.c",
    "./src/libgit2/cache.c",
    "./src/libgit2/submodule.c",
    "./src/libgit2/delta.c",
    "./src/libgit2/config_file.c",
    "./src/libgit2/object_api.c",
    "./src/libgit2/parse.c",
    "./src/libgit2/crlf.c",
    "./src/libgit2/diff_tform.c",
    "./src/libgit2/blob.c",
    "./src/libgit2/midx.c",
    "./src/libgit2/patch_parse.c",
    "./src/libgit2/clone.c",
    "./src/libgit2/diff_driver.c",
    "./src/libgit2/graph.c",
    "./src/libgit2/stash.c",
    "./src/libgit2/describe.c",
    "./src/libgit2/worktree.c",
    "./src/libgit2/rebase.c",
    "./src/libgit2/diff_parse.c",
    "./src/libgit2/blame_git.c",
    "./src/libgit2/buf.c",
    "./src/libgit2/mwindow.c",
    "./src/libgit2/message.c",
    "./src/libgit2/tree.c",
    "./src/libgit2/pathspec.c",
    "./src/libgit2/libgit2.c",
    "./src/libgit2/merge.c",
};
