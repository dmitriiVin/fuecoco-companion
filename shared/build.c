#include "fuecoco.h"
#include <ctype.h>
#include <dirent.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#ifdef __APPLE__
#include <sys/sysctl.h>
#endif

static const char *basename_of(const char *path) {
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}
static bool equal(const char *a, const char *b) { return strcmp(a, b) == 0; }
static bool one_of(const char *value, const char *const *words) {
    for (; *words; ++words) if (equal(value, *words)) return true;
    return false;
}
#define IN(value, ...) one_of(value, (const char *const[]){__VA_ARGS__, NULL})

static bool matches_build(int argc, const char *argv[]) {
    if (argc == 0) return false;
    const char *tool = basename_of(argv[0]);
    // npm changes its process title and places the script name inside argv[0].
    if (equal(tool, "npm run build") || !strncmp(tool, "npm run build:", 14)) return true;
    int i = 1;
    if (IN(tool, "sh", "bash", "dash", "zsh")) {
        return i < argc && equal(basename_of(argv[i]), "fuecoco-build");
    }
    if (equal(tool, "node") && i < argc) tool = basename_of(argv[i++]);
    if (!strncmp(tool, "python", 6) && i + 1 < argc && equal(argv[i], "-m"))
        return IN(argv[i + 1], "build", "PyInstaller", "nuitka");
    if (IN(tool, "gradle", "gradlew", "mvn", "mvnw", "tsc", "vite", "vite.js", "webpack", "webpack.js")) {
        for (int j = i; j < argc; ++j) if (IN(argv[j], "--watch", "-w", "--continuous")) return false;
    }
    if (IN(tool, "java", "javaw")) {
        for (; i < argc; ++i) {
            if (equal(argv[i], "org.gradle.wrapper.GradleWrapperMain")) { tool = "gradle"; ++i; break; }
            if (equal(argv[i], "org.codehaus.plexus.classworlds.launcher.Launcher")) { tool = "mvn"; ++i; break; }
        }
    }
    if (IN(tool, "gradle", "gradlew", "mvn", "mvnw")) {
        for (; i < argc; ++i) {
            const char *task = strrchr(argv[i], ':');
            task = task ? task + 1 : argv[i];
            if (IN(task, "build", "assemble", "assembleDebug", "assembleRelease", "bundle",
                   "compile", "package", "verify", "install", "test")) return true;
        }
        return false;
    }
    if (IN(tool, "swift-frontend", "swift-driver")) {
        for (; i < argc; ++i)
            if (IN(argv[i], "-c", "-emit-object", "-emit-module", "-emit-library", "-emit-executable")) return true;
        return false;
    }
    if (equal(tool, "esbuild")) {
        for (int j = i; j < argc; ++j)
            if (!strncmp(argv[j], "--service=", 10)) return false;
    }
    if (IN(tool, "esbuild", "webpack", "webpack.js")) {
        for (int j = i; j < argc; ++j)
            if (IN(argv[j], "serve", "--watch", "--help", "--version") || !strncmp(argv[j], "--serve=", 8)) return false;
        return true;
    }
    if (IN(tool, "make", "gmake", "ninja", "ninja-build", "xcodebuild", "clang", "clang++",
           "gcc", "g++", "cc", "cc1", "cc1plus", "ld", "ld.lld", "lld", "rustc", "swiftc",
           "javac", "tsc", "csc", "MSBuild", "fuecoco-build")) {
        for (; i < argc; ++i)
            if (IN(argv[i], "--watch", "--version", "-version", "--help", "-list", "-showBuildSettings", "-fsyntax-only", "-index-file")) return false;
        return true;
    }
    for (; i < argc; ++i) {
        const char *arg = argv[i];
        if (IN(tool,"flutter","dart","zig","deno","ng","parcel","vue-cli-service") &&
            IN(arg,"build","compile","bundle","build-exe","build-lib","build-obj")) return true;
        if (IN(tool,"cmake","meson") && IN(arg,"--build","compile","--install")) return true;
        if (IN(tool,"cargo","go","swift","dotnet","bazel","bazelisk","xcrun") &&
            IN(arg,"build","check","test","publish","install","msbuild","xcodebuild","swiftc","clang")) return true;
        if (IN(tool,"npm","npm-cli.js","yarn","yarn.js","pnpm","pnpm.cjs","bun","vite","vite.js","next","next.js","webpack","webpack.js","docker","podman") &&
            (equal(arg,"build") || !strncmp(arg,"build:",6))) return true;
        // A dev server, arbitrary script arguments, or a file named "build" is not a build subcommand.
        if (arg[0] != '-' && !IN(arg,"run","run-script","exec","buildx","compose","package")) break;
    }
    return false;
}

static bool packed_args(char *data, size_t length, int limit) {
    const char *args[192];
    int count = 0;
    while (length && count < limit && count < (int)(sizeof(args) / sizeof(*args))) {
        size_t n = strnlen(data, length);
        if (n == length) break;
        args[count++] = data;
        data += n + 1;
        length -= n + 1;
    }
    return matches_build(count, args);
}

#ifdef __APPLE__
static bool processes_building(void) {
    int list[] = {CTL_KERN, KERN_PROC, KERN_PROC_UID, (int)getuid()};
    size_t size = 0;
    if (sysctl(list, 4, NULL, &size, NULL, 0) != 0) return false;
    size += 32 * sizeof(struct kinfo_proc);
    struct kinfo_proc *procs = malloc(size);
    int argmax = 0;
    size_t argsize = sizeof(argmax);
    int maxkey[] = {CTL_KERN, KERN_ARGMAX};
    if (!procs || sysctl(list, 4, procs, &size, NULL, 0) != 0 ||
        sysctl(maxkey, 2, &argmax, &argsize, NULL, 0) != 0) { free(procs); return false; }
    char *buf = malloc(argmax);
    bool found = false;
    for (size_t i = 0; buf && i < size / sizeof(*procs) && !found; ++i) {
        int keys[] = {CTL_KERN, KERN_PROCARGS2, procs[i].kp_proc.p_pid};
        size_t len = argmax;
        if (sysctl(keys, 3, buf, &len, NULL, 0) != 0 || len <= sizeof(int)) continue;
        int argc;
        memcpy(&argc, buf, sizeof(argc));
        char *cursor = memchr(buf + sizeof(argc), 0, len - sizeof(argc));
        if (!cursor) continue;
        char *end = buf + len;
        while (cursor < end && !*cursor) ++cursor;
        found = packed_args(cursor, end - cursor, argc);
    }
    free(buf);
    free(procs);
    return found;
}
#else
static bool processes_building(void) {
    DIR *dir = opendir("/proc");
    if (!dir) return false;
    uid_t uid = getuid();
    struct dirent *entry;
    bool found = false;
    while (!found && (entry = readdir(dir))) {
        if (!isdigit((unsigned char)entry->d_name[0])) continue;
        char path[PATH_MAX], buf[32768];
        snprintf(path, sizeof(path), "/proc/%s/cmdline", entry->d_name);
        struct stat st;
        if (stat(path, &st) || st.st_uid != uid) continue;
        FILE *file = fopen(path, "rb");
        if (!file) continue;
        size_t n = fread(buf, 1, sizeof(buf), file);
        fclose(file);
        found = packed_args(buf, n, INT_MAX);
    }
    closedir(dir);
    return found;
}
#endif

static bool recent(const char *name, double seconds) {
    const char *cache = getenv("XDG_CACHE_HOME");
    const char *home = getenv("HOME");
    if (!home && (!cache || !*cache)) return false;
    char path[PATH_MAX];
    int n = snprintf(path, sizeof(path), "%s%s/fuecoco/%s", cache && *cache ? cache : home,
                     cache && *cache ? "" : "/.cache", name);
    struct stat st;
    if (n < 0 || (size_t)n >= sizeof(path) || stat(path, &st) != 0) return false;
    double age = difftime(time(NULL), st.st_mtime);
    return age >= 0 && age < seconds;
}
FCBuild fc_sample_build(void) {
    FCBuild result = {processes_building() || recent("last-success", 3), recent("last-error", 9)};
    return result;
}
