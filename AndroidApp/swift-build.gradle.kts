import org.gradle.api.tasks.Exec
import org.gradle.api.tasks.Sync

val dingerRepoRoot = rootProject.projectDir.parentFile
val dingerSwiftPackage = dingerRepoRoot.resolve("Packages/DingerCore")
val dingerSwiftSDKBase = System.getenv("SWIFT_SDK_PATH")?.let(::file)
    ?: file("${System.getProperty("user.home")}/Library/org.swift.swiftpm/swift-sdks")
val dingerSwiftSDK = dingerSwiftSDKBase.resolve("swift-6.3.3-RELEASE_android.artifactbundle/swift-android")
val dingerSwift = System.getenv("SWIFT_EXEC")?.let(::file)
    ?: file("${System.getProperty("user.home")}/.swiftly/bin/swift")
val dingerSQLiteOutput = rootProject.projectDir.resolve(".native/sqlite/arm64-v8a")
val dingerSQLiteInclude = dingerSQLiteOutput.resolve("sqlite-amalgamation-3470200")
val dingerBuildTriple = "aarch64-unknown-linux-android28"
val dingerStaticResources = dingerSwiftSDK.resolve("swift-resources/usr/lib/swift_static-aarch64")

val prepareDingerSQLite by tasks.registering(Exec::class) {
    workingDir(dingerRepoRoot)
    executable(dingerRepoRoot.resolve("scripts/build-android-sqlite.sh"))
    args("arm64-v8a")
    outputs.file(dingerSQLiteOutput.resolve("libsqlite3.a"))
    outputs.file(dingerSQLiteInclude.resolve("sqlite3.h"))
}

fun registerDingerSwiftBuild(configuration: String): TaskProvider<Exec> {
    val capitalized = configuration.replaceFirstChar { it.uppercaseChar() }
    return tasks.register<Exec>("buildDingerSwift$capitalized") {
        dependsOn(prepareDingerSQLite)
        workingDir(dingerSwiftPackage)
        executable(dingerSwift)
        args(
            "build",
            "--swift-sdk", dingerBuildTriple,
            "--build-system", "native",
            "--product", "DingerAndroidBridge",
            "-c", configuration,
            "-Xswiftc", "-static-stdlib",
            "-Xswiftc", "-resource-dir",
            "-Xswiftc", dingerStaticResources.absolutePath,
            "-Xcc", "-I${dingerSQLiteInclude.absolutePath}",
            "-Xlinker", "-L${dingerSQLiteOutput.absolutePath}"
        )
        inputs.dir(dingerSwiftPackage.resolve("Sources"))
        inputs.file(dingerSwiftPackage.resolve("Package.swift"))
        inputs.file(dingerSQLiteOutput.resolve("libsqlite3.a"))
        outputs.files(
            dingerSwiftPackage.resolve(".build/$dingerBuildTriple/$configuration/libDingerAndroidBridge.so")
        )
    }
}

fun registerDingerNativeCopy(configuration: String, buildTask: TaskProvider<Exec>): TaskProvider<Sync> {
    val capitalized = configuration.replaceFirstChar { it.uppercaseChar() }
    return tasks.register<Sync>("copyDingerNative$capitalized") {
        dependsOn(buildTask)
        from(dingerSwiftPackage.resolve(".build/$dingerBuildTriple/$configuration")) {
            include("libDingerAndroidBridge.so")
        }
        from(dingerSwiftSDK.resolve("ndk-sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"))
        into(layout.buildDirectory.dir("generated/jniLibs/$configuration/arm64-v8a"))
    }
}

val buildDingerSwiftDebug = registerDingerSwiftBuild("debug")
val buildDingerSwiftRelease = registerDingerSwiftBuild("release")
val copyDingerNativeDebug = registerDingerNativeCopy("debug", buildDingerSwiftDebug)
val copyDingerNativeRelease = registerDingerNativeCopy("release", buildDingerSwiftRelease)

afterEvaluate {
    tasks.named("mergeDebugJniLibFolders").configure { dependsOn(copyDingerNativeDebug) }
    tasks.named("mergeReleaseJniLibFolders").configure { dependsOn(copyDingerNativeRelease) }
}
