plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.xpertech.xsim.xsim"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"}

    defaultConfig {
        applicationId = "com.xpertech.xsim.xsim"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
    }
    }

    // PARCHE CRÍTICO PARA LIBRERÍAS SIN NAMESPACE (COMO BLUE_THERMAL_PRINTER)
    // Esto se ejecuta antes de que el compilador falle, asignando el ID necesario.
    project.subprojects {
        afterEvaluate {
            if (hasProperty("android")) {
                val androidExtension = extensions.findByName("android")
                if (androidExtension != null) {
                    try {
                        val setNamespaceMethod = androidExtension.javaClass.getMethod("setNamespace", String::class.java)
                        val getNamespaceMethod = androidExtension.javaClass.getMethod("getNamespace")

                        if (getNamespaceMethod.invoke(androidExtension) == null) {
                            // Forzamos el nombre del paquete de la librería
                            setNamespaceMethod.invoke(androidExtension, "com.lucaslsh.blue_thermal_printer")
                        }
                    } catch (e: Exception) {
                        // Si no se puede por reflexión, el sistema intentará el método estándar
                    }
                }
            }
        }
    }
}

flutter {
    source = "../.."
}