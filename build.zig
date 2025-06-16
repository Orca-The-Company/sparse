const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("sparse_lib", lib_mod);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "sparse",
        .root_module = lib_mod,
    });

    lib.linkLibC();

    lib.linkSystemLibrary("ssl");
    lib.linkSystemLibrary("pthread");
    if (b.lazyDependency(
        "libgit2",
        .{
            .target = target,
            .optimize = optimize,
            // .@"enable-ssh" = true, // optional ssh support via libssh2
            // .@"tls-backend" = .openssl, // use openssl instead of mbedtls
        },
    )) |libgit| {
        // using zig build system to fetch header files from libgit2
        lib.linkLibrary(libgit.artifact("git2"));
        //lib.installLibraryHeaders(libgit.artifact("git2"));
    }
    lib_mod.addIncludePath(b.path("gen"));

    switch (target.result.os.tag) {
        .driverkit, .ios, .macos, .tvos, .visionos, .watchos => {
            const apple_sdk = @import("apple_sdk");
            try apple_sdk.addPaths(b, lib);
        },
        .linux => {},
        else => @panic("target platform is not supported"),
    }

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "sparse",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    var test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
    {
        const helpgen_exe = b.addExecutable(.{
            .name = "helpgen",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/cli/helpgen.zig"),
                .target = b.graph.host,
            }),
        });
        const help_run = b.addRunArtifact(helpgen_exe);
        const output = help_run.captureStdOut();
        exe.root_module.addAnonymousImport(
            "help_strings",
            .{
                .root_source_file = output,
            },
        );
    }

    const integration_tests_step = step: {
        const integration_tests = b.addExecutable(.{
            .name = "sparse-integration-tests",
            .root_source_file = b.path("test/integration.zig"),
            .optimize = optimize,
            .target = target,
        });
        integration_tests.root_module.addImport("sparse", exe_mod);

        const integration_unit_tests = b.addTest(.{
            .root_module = integration_tests.root_module,
        });
        const run_integration_unit_tests = b.addRunArtifact(integration_unit_tests);

        const integration_tests_runner = b.addRunArtifact(integration_tests);
        integration_tests_runner.step.dependOn(&run_integration_unit_tests.step);

        const test_options = b.addOptions();
        test_options.addOptionPath("sparse_exe_path", exe.getEmittedBin());
        test_options.addOption([]const u8, "output_dir", b.exe_dir);
        integration_tests.root_module.addOptions("build_options", test_options);
        //integration_tests_runner.addArg(exe.getEmittedBin().generated.sub_path);

        const integration_step = b.step("test-integration", "Run integration tests for sparse");
        integration_step.dependOn(&integration_tests_runner.step);
        break :step integration_step;
    };

    integration_tests_step.dependOn(test_step);
}
