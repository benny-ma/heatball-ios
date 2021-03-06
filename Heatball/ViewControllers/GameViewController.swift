//
//  GameViewController.swift
//  Heatball
//
//  Created by Atilla Özder on 11.05.2020.
//  Copyright © 2020 Atilla Özder. All rights reserved.
//

import UIKit
import SpriteKit
import GameKit
import GoogleMobileAds

// MARK: - GameState
enum GameState: Int {
    case playing = 0
    case advertisement = 1
    case adPresented = 2
    case paused = 3
    case continued = 4
    case home
    case settings
    case leaderboard
}

// MARK: - GameViewController
class GameViewController: UIViewController {
    
    // MARK: - Properties
    var skView: SKView {
        return self.view as! SKView
    }

    var gameScene: GameScene {
        return skView.scene as? GameScene ?? .init()
    }

    private lazy var adHelper = AdHelper(rootViewController: self)
    private var previousGameState: GameState = .playing

    private var menus: [UIView] {
        return [
            playingMenu, pauseMenu, advertisementMenu, settingsMenu, homeMenu]
    }

    var gameState: GameState = .home {
        didSet {
            menus.forEach { $0.isHidden = true }
            let shouldPresentNewMenu = previousGameState.rawValue < 5 && gameState == .home

            switch gameState {
            case .advertisement, .adPresented, .paused:
                AudioPlayer.shared.pauseMusic()
            default:
                AudioPlayer.shared.playMusic()
            }

            if shouldPresentNewMenu {
                homeMenu.isHidden = false
                presentMenuScene()
            } else {
                switch gameState {
                case .home:
                    homeMenu.isHidden = false
                case .advertisement:
                    playingMenu.isHidden = false
                    advertisementMenu.isHidden = false
                case .leaderboard:
                    homeMenu.isHidden = false
                    presentLeaderboard()
                case .settings:
                    settingsMenu.isHidden = false
                case .playing:
                    presentGameScene()
                case .adPresented:
                    playingMenu.isHidden = false
                    adHelper.presentRewardedAd()
                case .paused:
                    gameScene.setPausedAndNotify(true)
                    playingMenu.isHidden = false
                    pauseMenu.isHidden = false
                case .continued:
                    gameScene.setPausedAndNotify(false)
                    playingMenu.isHidden = false
                }
            }

            previousGameState = gameState
        }
    }

    private lazy var homeMenu = HomeMenu()
    private lazy var advertisementMenu = AdvertisementMenu()
    private lazy var settingsMenu = SettingsMenu()
    private lazy var playingMenu = PlayingMenu()
    private lazy var pauseMenu = PauseMenu()

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    // MARK: - View Life Cycle

    override func loadView() {
        view = SKView(frame: UIScreen.main.bounds)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if #available(iOS 11.0, *) {
            gameScene.insets = view.safeAreaInsets
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        presentEmptyScene()
        registerRemoteNotifications()
        setupMenus()
        gameState = .home
        adHelper.delegate = self
        checkSession()

        NotificationCenter.default.addObserver(self, selector: #selector(setStayPaused), name: .shouldStayPausedNotification, object: nil)
    }

    @objc
    func setStayPaused() {
        if gameState == .paused || gameState == .advertisement {
            gameScene.setStayPaused()
        }
    }

    // MARK: - Private Helper Methods
    private func setupMenus() {
        menus.forEach { (menu) in
            self.view.addSubview(menu)
            menu.pinEdgesToUnsafeArea()
        }

        homeMenu.delegate = self
        advertisementMenu.delegate = self
        playingMenu.delegate = self
        pauseMenu.delegate = self
        settingsMenu.delegate = self
    }

    private func checkSession() {
        if #available(iOS 10.3, *) {
            let session = UserDefaults.standard.session
            guard session > 0 &&
                session.truncatingRemainder(dividingBy: 4) == 0 else {
                    return
            }

            DispatchQueue.main.async {
                SKStoreReviewController.requestReview()
            }
        }
    }

    private func presentLeaderboard() {
        if GameManager.shared.gcEnabled {
            let viewController = GKGameCenterViewController()
            viewController.gameCenterDelegate = self
            viewController.viewState = .leaderboards
            viewController.leaderboardIdentifier = GameManager.leaderboardID
            self.present(viewController, animated: true, completion: nil)
        } else {
            let alertController = UIAlertController(
                title: "Heatball",
                message: MainStrings.gcErrorMessage.localized,
                preferredStyle: .alert)

            let dismissAction = UIAlertAction(
                title: MainStrings.okTitle.localized, style: .cancel, handler: nil)
            alertController.addAction(dismissAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }

    private func presentEmptyScene() {
        let scene = SKScene(size: skView.frame.size)
        scene.scaleMode = .aspectFit
        scene.backgroundColor = .background
        skView.presentScene(scene)
    }

    private func presentMenuScene() {
        let scene = MenuScene(size: skView.frame.size)
        scene.scaleMode = .aspectFit
        if #available(iOS 11.0, *) {
            scene.insets = skView.safeAreaInsets
        }

        skView.ignoresSiblingOrder = true
        skView.presentScene(scene)
    }

    private func presentGameScene() {
        let scene = GameScene(size: skView.frame.size)
        scene.scaleMode = .aspectFit
        scene.sceneDelegate = self

        if let menuScene = skView.scene as? MenuScene {
            scene.insets = menuScene.insets
        } else {
            if #available(iOS 11.0, *) {
                scene.insets = skView.safeAreaInsets
            }
        }

        skView.ignoresSiblingOrder = true
        skView.presentScene(scene)
        playingMenu.reset()
    }

    private func rate() {
        if #available(iOS 10.3, *) {
            DispatchQueue.main.async {
                SKStoreReviewController.requestReview()
            }
        } else {
            let urlString = "https://itunes.apple.com/app/id\(GameManager.appID)?action=write-review"
            URLNavigator.shared.open(urlString)
        }
    }

    private func share() {
        if let url = URL(string: "https://apps.apple.com/app/id\(GameManager.appID)") {
            let viewController = UIActivityViewController(
                activityItems: [url], applicationActivities: nil)
            viewController.popoverPresentationController?.sourceView = self.view
            viewController.popoverPresentationController?.sourceRect = .zero
            self.present(viewController, animated: true, completion: nil)
        }
    }

    private func registerRemoteNotifications() {
        if #available(iOS 10.0, *) {
            let options: UNAuthorizationOptions = [.alert, .badge, .sound]
            UNUserNotificationCenter.current()
                .requestAuthorization(options: options) { (_, _) in
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
            }
        } else {
            let options: UIUserNotificationType = [.alert, .badge, .sound]
            let settings = UIUserNotificationSettings(types: options, categories: nil)
            UIApplication.shared.registerUserNotificationSettings(settings)
        }
    }
}

extension GameViewController: AdHelperDelegate {
    private func setStateHome() {
        gameState = .home
    }

    func adHelper(_ adHelper: AdHelper, userDidEarn reward: GADAdReward?) {
        reward == nil ? setStateHome() : gameScene.didGetReward()
    }

    func adHelper(_ adHelper: AdHelper, willPresentRewardedAd isReady: Bool) {
        isReady ? gameScene.willPresentRewardBasedVideoAd() : setStateHome()
    }
}

extension GameViewController: SceneDelegate {
    func scene(_ scene: GameScene, didUpdateScore score: Double) {
        playingMenu.setScore(score)
    }

    func scene(_ scene: GameScene, willUpdateLifeCount count: Int) {
        playingMenu.setLifeCount(count)
    }

    func scene(_ scene: GameScene, didFinishGameWithScore score: Double) {
        UserDefaults.standard.setScore(Int(score))
        let gameCount = GameManager.shared.gameCount
        if gameCount.remainder(dividingBy: 2) == 0 {
            adHelper.presentInterstitial()
        }
    }

    func scene(_ scene: GameScene, didUpdateGameState state: GameState) {
        gameState = state
    }
}

// MARK: - MenuDelegate
extension GameViewController: MenuDelegate {
    func menu(_ menu: Menu, didUpdateGameState gameState: GameState) {
        self.gameState = gameState
    }

    func menu(_ menu: Menu, didSelectOption option: MenuOption) {
        switch option {
        case .rate:
            rate()
        }
    }
}

// MARK: - SettingsMenuDelegate
extension GameViewController: SettingsMenuDelegate {
    func settingsMenu(_ settingsMenu: SettingsMenu, didSelectOption option: SettingsMenuOption) {
        switch option {
        case .otherApps:
            let urlString = "itms-apps://itunes.apple.com/developer/atilla-ozder/id1440770128?mt=8"
            URLNavigator.shared.open(urlString)
        case .privacy:
            let urlString = "http://www.atillaozder.com/privacy-policy"
            URLNavigator.shared.open(urlString)
        case .share:
            share()
        case .support:
            let urlString = "http://www.atillaozder.com"
            URLNavigator.shared.open(urlString)
        case .back:
            gameState = .home
        }
    }
}

extension GameViewController: GKGameCenterControllerDelegate {
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true, completion: nil)
    }
}
