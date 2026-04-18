allprojects {
    repositories {
        google()
        maven { url = uri("https://repo1.maven.org/maven2/") }
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
    
    configurations.all {
        resolutionStrategy {
            force("com.android.tools.build:gradle:8.11.1")
            force("com.android.tools.build:builder:8.11.1")
            force("com.android.tools.build:apkzlib:8.11.1")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
