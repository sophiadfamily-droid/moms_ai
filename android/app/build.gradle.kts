import java.io.File
import java.util.Properties
import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputFile
import org.gradle.api.tasks.Optional
import org.gradle.api.tasks.TaskAction

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

abstract class ValidateReleaseSigning : DefaultTask() {
    @get:InputFile
    @get:Optional
    abstract val propertiesFile: RegularFileProperty

    @get:Input
    abstract val androidProjectDirectoryPath: Property<String>

    @TaskAction
    fun validateSigningConfiguration() {
        val configuredPropertiesFile = propertiesFile.get().asFile
        if (!configuredPropertiesFile.isFile) {
            throw GradleException(
                "Android Release signing configuration is missing: android/key.properties.",
            )
        }

        val configuredProperties = Properties()
        configuredPropertiesFile.inputStream().use(configuredProperties::load)
        val requiredProperties = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        val missingProperties =
            requiredProperties.filter {
                configuredProperties.getProperty(it).isNullOrBlank()
            }
        if (missingProperties.isNotEmpty()) {
            throw GradleException(
                "Android Release signing configuration is incomplete. Missing properties: " +
                    missingProperties.joinToString(", "),
            )
        }

        val configuredStorePath = File(configuredProperties.getProperty("storeFile"))
        val configuredStoreFile =
            if (configuredStorePath.isAbsolute) {
                configuredStorePath
            } else {
                File(androidProjectDirectoryPath.get(), configuredStorePath.path)
            }
        if (!configuredStoreFile.isFile) {
            throw GradleException(
                "Android Release signing keystore does not exist at the configured storeFile path.",
            )
        }
    }
}

val releaseSigningPropertiesFile = rootProject.file("key.properties")
val requiredReleaseSigningProperties =
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val releaseSigningProperties = Properties()

if (releaseSigningPropertiesFile.exists()) {
    releaseSigningPropertiesFile.inputStream().use(releaseSigningProperties::load)
}

val missingReleaseSigningProperties =
    requiredReleaseSigningProperties.filter {
        releaseSigningProperties.getProperty(it).isNullOrBlank()
    }

val releaseKeystoreFile =
    releaseSigningProperties.getProperty("storeFile")?.takeIf { it.isNotBlank() }?.let {
        val configuredPath = File(it)
        // Relative paths are resolved from the Android project directory.
        if (configuredPath.isAbsolute) configuredPath else rootProject.file(it)
    }

val validateReleaseSigning =
    tasks.register<ValidateReleaseSigning>("validateReleaseSigning") {
        group = "verification"
        description = "Validates the local Android Release signing configuration."
        propertiesFile.set(rootProject.layout.projectDirectory.file("key.properties"))
        androidProjectDirectoryPath.set(rootProject.layout.projectDirectory.asFile.absolutePath)
    }

val releaseArtifactTaskName = Regex("^(assemble|bundle|package).*Release.*$")
tasks.configureEach {
    if (releaseArtifactTaskName.matches(name)) {
        dependsOn(validateReleaseSigning)
    }
}

android {
    namespace = "com.sophiadfamily.zeliaaiapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        multiDexEnabled = true
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.sophiadfamily.zeliaaiapp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (missingReleaseSigningProperties.isEmpty()) {
                storeFile = releaseKeystoreFile
                storePassword = releaseSigningProperties.getProperty("storePassword")
                keyAlias = releaseSigningProperties.getProperty("keyAlias")
                keyPassword = releaseSigningProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
