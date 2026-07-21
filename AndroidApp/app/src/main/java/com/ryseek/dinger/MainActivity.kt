package com.ryseek.dinger

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ryseek.dinger.ui.DingerApp
import com.ryseek.dinger.ui.DingerViewModel
import com.ryseek.dinger.ui.theme.DingerTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            DingerTheme {
                DingerApp(viewModel<DingerViewModel>())
            }
        }
    }
}
