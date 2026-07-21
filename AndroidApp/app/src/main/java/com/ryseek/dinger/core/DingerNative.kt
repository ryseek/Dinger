package com.ryseek.dinger.core

object DingerNative {
    init {
        System.loadLibrary("DingerAndroidBridge")
    }

    external fun open(databasePath: String): String
    external fun call(requestJSON: String): String
}
