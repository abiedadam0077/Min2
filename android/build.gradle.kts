allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Android Lint runs inside plugin modules too (for example file_selector_android). Its analysis
// can crash on CI images without affecting the build, so every lint task is disabled. The release
// gate is `flutter analyze` plus the test suite.
allprojects {
    tasks.matching { it.name.lowercase().contains("lint") }.configureEach {
        enabled = false
    }
}
