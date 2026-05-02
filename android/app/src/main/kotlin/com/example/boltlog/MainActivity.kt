package com.example.boltlog

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.firebase.ui.auth.FirebaseAuthUIActivityResultContract
import com.firebase.ui.auth.data.model.FirebaseAuthUIAuthenticationResult
import com.firebase.ui.auth.AuthUI
import com.google.firebase.auth.ActionCodeSettings
import com.google.firebase.auth.FirebaseAuth
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    companion object {
        private const val RC_SIGN_IN = 100
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleEmailLinkIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleEmailLinkIntent(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        if (requestCode == RC_SIGN_IN) {
            val response = FirebaseAuthUIActivityResultContract().parseResult(resultCode, data)
            onSignInResult(response)
        }
    }

    private fun onSignInResult(result: FirebaseAuthUIAuthenticationResult) {
        val response = result.idpResponse
        if (result.resultCode == Activity.RESULT_OK) {
            // Successfully signed in
            val user = FirebaseAuth.getInstance().currentUser
            // Handle successful sign-in
            // You can send this result to Flutter via method channel if needed
        } else {
            // Sign in failed. If response is null the user canceled the
            // sign-in flow using the back button. Otherwise check
            // response.getError().getErrorCode() and handle the error.
            if (response == null) {
                // User canceled the sign-in flow
                // Handle user cancellation
            } else {
                // Sign-in error occurred
                val error = response.error
                if (error != null) {
                    val errorCode = error.errorCode
                    // Handle the error based on errorCode
                    // You can send this error to Flutter via method channel if needed
                }
            }
        }
    }

    private fun getProviders(): ArrayList<AuthUI.IdpConfig> {
        // Configure ActionCodeSettings for email link sign-in
        val actionCodeSettings = ActionCodeSettings.newBuilder()
            .setAndroidPackageName(
                "com.example.boltlog", // yourPackageName
                true, // installIfNotAvailable
                null, // minimumVersion
            )
            .setHandleCodeInApp(true) // This must be set to true
            .setUrl("https://google.com") // This URL needs to be whitelisted
            .build()

        // Choose authentication providers
        return arrayListOf(
            AuthUI.IdpConfig.EmailBuilder()
                .enableEmailLinkSignIn()
                .setActionCodeSettings(actionCodeSettings)
                .build(),
            AuthUI.IdpConfig.PhoneBuilder().build(),
            AuthUI.IdpConfig.GoogleBuilder().build(),
            AuthUI.IdpConfig.FacebookBuilder().build(),
            AuthUI.IdpConfig.TwitterBuilder().build(),
        )
    }

    private fun handleEmailLinkIntent(intent: Intent?) {
        if (intent == null) return
        
        if (AuthUI.canHandleIntent(intent)) {
            val extras = intent.extras ?: return
            val link = extras.getString("email_link_sign_in")
            if (link != null) {
                val providers = getProviders()
                val signInIntent = AuthUI.getInstance()
                    .createSignInIntentBuilder()
                    .setEmailLink(link)
                    .setAvailableProviders(providers)
                    .build()
                startActivityForResult(signInIntent, RC_SIGN_IN)
            }
        }
    }

    fun launchSignIn() {
        val providers = getProviders()

        // Create and launch sign-in intent
        val signInIntent = AuthUI.getInstance()
            .createSignInIntentBuilder()
            .setAvailableProviders(providers)
            .build()
        startActivityForResult(signInIntent, RC_SIGN_IN)
    }

    fun signOut() {
        AuthUI.getInstance()
            .signOut(this@MainActivity)
            .addOnCompleteListener { task ->
                if (task.isSuccessful) {
                    // Sign out completed successfully
                    // Handle sign out completion
                    // You can send this result to Flutter via method channel if needed
                } else {
                    // Sign out failed
                    val exception = task.exception
                    // Handle error
                    // You can send this error to Flutter via method channel if needed
                }
            }
    }

    fun deleteAccount() {
        AuthUI.getInstance()
            .delete(this@MainActivity)
            .addOnCompleteListener { task ->
                if (task.isSuccessful) {
                    // Account deletion completed successfully
                    // Handle account deletion completion
                    // You can send this result to Flutter via method channel if needed
                } else {
                    // Account deletion failed
                    val exception = task.exception
                    // Handle error
                    // You can send this error to Flutter via method channel if needed
                }
            }
    }
}
