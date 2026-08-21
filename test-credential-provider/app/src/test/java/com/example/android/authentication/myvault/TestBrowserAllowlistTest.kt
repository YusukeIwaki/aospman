/*
 * Copyright 2026 Yusuke Iwaki
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 */
package com.example.android.authentication.myvault

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TestBrowserAllowlistTest {
    @Test
    fun authorizesOnlyPinnedTestBrowserIdentity() {
        val allowlist = TestBrowserAllowlist.JSON

        assertTrue(allowlist.contains("com.example.webviewpasskeybrowser.browser"))
        assertTrue(
            allowlist.contains(
                "D6:B8:90:EC:A6:F4:70:8A:FF:24:BE:19:17:6C:56:AF:" +
                    "EE:38:D8:D4:D5:61:2A:99:64:F5:F5:81:CC:C2:B4:B1",
            ),
        )
        assertFalse(allowlist.contains("com.android.chrome"))
        assertFalse(allowlist.contains("com.google.android.gms"))
    }
}
