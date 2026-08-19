package com.example.webviewpasskeybrowser

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.os.Bundle
import android.util.Log
import android.webkit.ConsoleMessage
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewFeature
import com.example.webviewpasskeybrowser.theme.WebViewPasskeyBrowserTheme

private const val TAG = "WebViewPasskey"
private const val TEST_URL = "https://passkey-test-lab-production.up.railway.app/"

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContent {
            WebViewPasskeyBrowserTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background,
                ) {
                    BrowserScreen()
                }
            }
        }
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun BrowserScreen() {
    val context = LocalContext.current
    var address by rememberSaveable { mutableStateOf(TEST_URL) }
    var status by remember { mutableStateOf("WebViewを初期化中") }
    var webView by remember { mutableStateOf<WebView?>(null) }
    val modeName = if (BuildConfig.WEB_AUTH_BROWSER_MODE) "BROWSER treatment" else "DEFAULT control"

    BackHandler(enabled = webView?.canGoBack() == true) {
        webView?.goBack()
    }

    DisposableEffect(Unit) {
        onDispose {
            webView?.destroy()
            webView = null
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .safeDrawingPadding(),
    ) {
        Text(
            text = "WebView Passkey Browser — $modeName",
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
            style = MaterialTheme.typography.titleSmall,
        )
        Text(
            text = status,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 2.dp),
            style = MaterialTheme.typography.bodySmall,
            color = Color.DarkGray,
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            OutlinedTextField(
                value = address,
                onValueChange = { address = it },
                modifier = Modifier.weight(1f),
                label = { Text("URL") },
                singleLine = true,
            )
            Button(onClick = { webView?.loadUrl(normalizeUrl(address)) }) {
                Text("開く")
            }
            Button(onClick = { webView?.reload() }) {
                Text("再読込")
            }
        }

        AndroidView(
            modifier = Modifier.weight(1f),
            factory = {
                WebView.setWebContentsDebuggingEnabled(true)
                WebView(context).apply {
                    webView = this
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    settings.cacheMode = WebSettings.LOAD_DEFAULT
                    CookieManager.getInstance().setAcceptCookie(true)
                    CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)

                    val featureSupported = WebViewFeature.isFeatureSupported(
                        WebViewFeature.WEB_AUTHENTICATION,
                    )
                    if (featureSupported && BuildConfig.WEB_AUTH_BROWSER_MODE) {
                        WebSettingsCompat.setWebAuthenticationSupport(
                            settings,
                            WebSettingsCompat.WEB_AUTHENTICATION_SUPPORT_FOR_BROWSER,
                        )
                    }
                    val configuredSupport = if (featureSupported) {
                        WebSettingsCompat.getWebAuthenticationSupport(settings)
                    } else {
                        -1
                    }
                    val packageInfo = WebView.getCurrentWebViewPackage()
                    val diagnostic = "feature=$featureSupported support=$configuredSupport " +
                        "provider=${packageInfo?.packageName}@${packageInfo?.versionName}"
                    status = diagnostic
                    Log.i(TAG, "$modeName $diagnostic package=${BuildConfig.APPLICATION_ID}")

                    webChromeClient = object : WebChromeClient() {
                        override fun onConsoleMessage(consoleMessage: ConsoleMessage): Boolean {
                            Log.i(
                                TAG,
                                "console ${consoleMessage.messageLevel()} " +
                                    "${consoleMessage.sourceId()}:${consoleMessage.lineNumber()} " +
                                    consoleMessage.message(),
                            )
                            return true
                        }
                    }
                    webViewClient = object : WebViewClient() {
                        override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
                            address = url
                            status = "読込中: $url"
                            Log.i(TAG, "page-start $url")
                        }

                        override fun onPageFinished(view: WebView, url: String) {
                            address = url
                            view.evaluateJavascript(
                                "(() => {" +
                                    "const probe={origin:location.origin," +
                                    "credentials:Boolean(navigator.credentials)," +
                                    "conditionalApi:Boolean(window.PublicKeyCredential)&&" +
                                    "typeof window.PublicKeyCredential." +
                                    "isConditionalMediationAvailable==='function'};" +
                                    "if(probe.conditionalApi){" +
                                    "window.PublicKeyCredential.isConditionalMediationAvailable()" +
                                    ".then(v=>console.log('AOSPMAN_CONDITIONAL_AVAILABLE '+v))" +
                                    ".catch(e=>console.log('AOSPMAN_CONDITIONAL_ERROR ' +" +
                                    "e.name + ':' + e.message));}" +
                                    "return JSON.stringify(probe);})()",
                            ) { result ->
                                status = "$modeName $result"
                                Log.i(TAG, "page-finished $url capabilities=$result")
                            }
                        }

                        override fun onReceivedError(
                            view: WebView,
                            request: WebResourceRequest,
                            error: WebResourceError,
                        ) {
                            Log.e(
                                TAG,
                                "web-error main=${request.isForMainFrame} " +
                                    "code=${error.errorCode} description=${error.description}",
                            )
                        }
                    }
                    loadUrl(TEST_URL)
                }
            },
        )
    }
}

private fun normalizeUrl(value: String): String {
    val trimmed = value.trim()
    return if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
        trimmed
    } else {
        "https://$trimmed"
    }
}
