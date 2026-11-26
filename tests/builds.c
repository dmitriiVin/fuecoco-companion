// Exercise the matcher with actual argv boundaries, including process-title rewrites.
#include "../shared/build.c"
#include <assert.h>
#define CASE(want, ...) do { const char *v[] = {__VA_ARGS__}; assert(matches_build(sizeof(v)/sizeof(v[0]), v) == want); } while (0)
int main(void) {
    CASE(true, "/usr/bin/make", "-j4");
    CASE(true, "cargo", "build", "--release");
    CASE(true, "node", "/path/to/npm-cli.js", "run", "build:web");
    CASE(true, "npm run build:web");
    CASE(true, "gradle", "clean", ":app:assembleDebug");
    CASE(true, "java", "-Xmx2G", "org.codehaus.plexus.classworlds.launcher.Launcher", "clean", "package");
    CASE(true, "cmake", "--build", "out");
    CASE(true, "python3", "-m", "build");
    CASE(true, "/bin/sh", "/bin/fuecoco-build", "custom");
    CASE(false, "npm", "run", "dev", "--", "build");
    CASE(false, "tsc", "--watch");
    CASE(false, "java", "org.gradle.launcher.daemon.bootstrap.GradleDaemon", "8.7");
    CASE(false, "bash", "-c", "echo cargo build");
    CASE(true, "swift-frontend", "-frontend", "-c", "main.swift");
    CASE(false, "swift-frontend", "-frontend", "-typecheck", "main.swift");
    CASE(true, "clang", "-w", "-c", "main.c");
    CASE(true, "webpack", "--mode", "production");
    CASE(false, "webpack", "serve");
    CASE(true, "flutter", "build", "apk");
    CASE(false, "flutter", "daemon");
    CASE(false, "clangd", "--background-index");
    CASE(false, "xcodebuild", "-list");
    if (getenv("PROBE_ONLY")) return fc_sample_build().building ? 0 : 1;
    puts("Build matcher passed");
}
