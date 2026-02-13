//
//  AudioRouteMonitor.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/2/10.
//

import AVFoundation

final class AudioRouteMonitor {
    private var onChange: (() -> Void)?

    func start(onChange: @escaping () -> Void) {
        self.onChange = onChange
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(routeChanged(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        onChange = nil
    }

    @objc private func routeChanged(_ note: Notification) {
        onChange?()
    }
}
