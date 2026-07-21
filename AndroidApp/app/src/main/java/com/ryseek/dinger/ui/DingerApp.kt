package com.ryseek.dinger.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CollectionsBookmark
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController

private const val HomeRoute = "home"
private const val EntryRoute = "entry"
private const val DeckRoute = "deck"
private const val CardRoute = "card"
private const val QuizRoute = "quiz"

@Composable
fun DingerApp(viewModel: DingerViewModel) {
    val state by viewModel.state.collectAsState()
    val navController = rememberNavController()
    val snackbars = remember { SnackbarHostState() }
    val exportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { uri ->
        if (uri == null) viewModel.clearExport() else viewModel.writeExport(uri)
    }
    val importLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri -> uri?.let(viewModel::importDecks) }

    LaunchedEffect(state.error, state.notice) {
        val message = state.error ?: state.notice ?: return@LaunchedEffect
        snackbars.showSnackbar(message)
        viewModel.dismissMessage()
    }
    LaunchedEffect(state.exportedFile) {
        state.exportedFile?.let { exportLauncher.launch(it.filename) }
    }
    val currentRoute = navController.currentBackStackEntryAsState().value?.destination?.route
    LaunchedEffect(state.quizState) {
        if (state.quizState != null && currentRoute != QuizRoute) navController.navigate(QuizRoute)
    }

    Scaffold(snackbarHost = { SnackbarHost(snackbars) }) { outerPadding ->
        if (state.initializing) {
            Box(
                Modifier.fillMaxSize().padding(outerPadding).testTag("startup"),
                contentAlignment = Alignment.Center,
            ) {
                androidx.compose.foundation.layout.Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator()
                    Text(state.startupMessage, style = MaterialTheme.typography.bodyLarge)
                }
            }
        } else {
            DingerNavigation(
                state = state,
                viewModel = viewModel,
                navController = navController,
                onImport = { importLauncher.launch(arrayOf("application/json", "text/json", "*/*")) },
                modifier = Modifier.padding(outerPadding),
            )
        }
    }
}

@Composable
private fun DingerNavigation(
    state: AppUiState,
    viewModel: DingerViewModel,
    navController: NavHostController,
    onImport: () -> Unit,
    modifier: Modifier = Modifier,
) {
    NavHost(navController, startDestination = HomeRoute, modifier = modifier) {
        composable(HomeRoute) {
            HomeScreen(
                state = state,
                viewModel = viewModel,
                onEntry = { hit -> viewModel.openEntry(hit); navController.navigate(EntryRoute) },
                onDeck = { id -> viewModel.openDeck(id); navController.navigate(DeckRoute) },
                onImport = onImport,
            )
        }
        composable(EntryRoute) {
            EntryScreen(state, viewModel, onBack = navController::popBackStack)
        }
        composable(DeckRoute) {
            DeckDetailScreen(
                state,
                viewModel,
                onBack = navController::popBackStack,
                onCard = { row -> viewModel.openCard(row); navController.navigate(CardRoute) },
            )
        }
        composable(CardRoute) {
            CardScreen(state, viewModel, onBack = navController::popBackStack) {
                navController.popBackStack(DeckRoute, inclusive = false)
            }
        }
        composable(QuizRoute) {
            QuizPlayScreen(state, viewModel) {
                viewModel.cancelQuiz()
                navController.popBackStack(QuizRoute, inclusive = true)
            }
        }
    }
}

private data class HomeTab(val label: String, val icon: @Composable () -> Unit)

@Composable
private fun HomeScreen(
    state: AppUiState,
    viewModel: DingerViewModel,
    onEntry: (com.ryseek.dinger.core.SenseHit) -> Unit,
    onDeck: (Long) -> Unit,
    onImport: () -> Unit,
) {
    var selected by rememberSaveable { mutableIntStateOf(0) }
    val tabs = listOf(
        HomeTab("Dictionary") { Icon(Icons.Default.Search, null) },
        HomeTab("Cards") { Icon(Icons.Default.CollectionsBookmark, null) },
        HomeTab("Quiz") { Icon(Icons.Default.PlayCircle, null) },
    )
    Scaffold(
        bottomBar = {
            NavigationBar {
                tabs.forEachIndexed { index, tab ->
                    NavigationBarItem(
                        selected = selected == index,
                        onClick = { selected = index },
                        icon = tab.icon,
                        label = { Text(tab.label) },
                        modifier = Modifier.testTag("tab-${tab.label.lowercase()}")
                    )
                }
            }
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when (selected) {
                0 -> DictionaryScreen(state, viewModel, onEntry)
                1 -> DecksScreen(state, viewModel, onDeck, onImport)
                else -> QuizSetupScreen(state, viewModel)
            }
            if (state.busy || state.quizLoading) {
                CircularProgressIndicator(Modifier.align(Alignment.TopCenter).testTag("busy"))
            }
        }
    }
}
