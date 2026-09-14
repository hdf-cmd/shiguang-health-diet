pluginManagement {
    repositories {
        maven("https://mirrors.aliyun.com/gradle-plugin-portal") { isAllowInsecureProtocol = false }
        maven("https://mirrors.aliyun.com/repository/google")
        maven("https://mirrors.aliyun.com/repository/central")
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        maven("https://mirrors.aliyun.com/repository/google")
        maven("https://mirrors.aliyun.com/repository/central")
        google()
        mavenCentral()
    }
}

rootProject.name = "HealthyDiet"
include(":app")
