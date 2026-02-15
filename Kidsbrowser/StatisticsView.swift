//
//  StatisticsView.swift
//  Kidsbrowser
//
//  Created by BriceM4 on 17/01/2026.
//

import SwiftUI
import AVKit

struct StatisticsView: View {
    @State private var history: [HistoryItem] = []
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Chargement des stats...")
            } else if history.isEmpty {
                VStack {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    Text("Aucun historique pour le moment.")
                        .foregroundColor(.gray)
                }
            } else {
                List {
                    // On groupe par date (Heure par Heure pour simuler des "Sessions")
                    let grouped = Dictionary(grouping: history) { item in
                        String(item.created_at.prefix(13)) // YYYY-MM-DDTHH
                    }
                    
                    let sortedKeys = grouped.keys.sorted().reversed()
                    
                    ForEach(sortedKeys, id: \.self) { dateKey in
                        Section(header: Text(formatSessionDate(dateKey))) {
                            ForEach(grouped[dateKey]!) { item in
                                NavigationLink(destination: DetailStatView(item: item)) {
                                    HStack {
                                        iconForType(item.game_type)
                                            .foregroundColor(.blue)
                                            .frame(width: 30)
                                        
                                        VStack(alignment: .leading) {
                                            Text(titleForType(item.game_type))
                                                .font(.headline)
                                            
                                            if item.game_type == "lecture" {
                                                Text("Durée : \(item.details.duration_seconds ?? 0) sec")
                                                    .font(.caption).foregroundColor(.gray)
                                            } else if let mistakes = item.details.mistakes {
                                                Text("Fautes : \(mistakes)")
                                                    .font(.caption).foregroundColor(mistakes > 0 ? .red : .green)
                                            }
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Statistiques 📊")
        .onAppear { loadData() }
    }
    
    func loadData() {
        Task {
            do {
                let items = try await SupabaseManager.shared.fetchHistory()
                await MainActor.run {
                    self.history = items
                    self.isLoading = false
                }
            } catch {
                print("Erreur stats: \(error)")
                await MainActor.run { isLoading = false }
            }
        }
    }
    
    func formatSessionDate(_ isoString: String) -> String {
        let datePart = isoString.prefix(10)
        let hourPart = isoString.suffix(2)
        return "Session du \(datePart) vers \(hourPart)h"
    }
    
    func iconForType(_ type: String) -> Image {
        switch type.lowercased() {
        case "lecture": return Image(systemName: "mic.fill")
        case "math": return Image(systemName: "number.circle.fill")
        case "quiz": return Image(systemName: "pencil.and.scribble")
        case "write": return Image(systemName: "keyboard.fill")
        default: return Image(systemName: "star.fill")
        }
    }
    
    func titleForType(_ type: String) -> String {
        switch type.lowercased() {
        case "lecture": return "Lecture à voix haute"
        case "math": return "Calcul Mental"
        case "quiz": return "Orthographe (Quiz)"
        case "write": return "Écriture (Clavier)"
        default: return "Exercice"
        }
    }
}

// --- VUE DÉTAILLÉE (LECTEUR AUDIO + RÉSULTATS) ---

struct DetailStatView: View {
    let item: HistoryItem
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var playbackObserver: NSObjectProtocol?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                
                // EN-TÊTE
                HStack {
                    Image(systemName: "calendar")
                    Text("Fait le \(formatDate(item.created_at))")
                }
                .foregroundColor(.gray)
                .padding(.top)
                
                if item.game_type.lowercased() == "lecture" {
                    // --- AFFICHAGE LECTURE ---
                    VStack(spacing: 20) {
                        Text("⏱️ Temps : \(item.details.duration_seconds ?? 0) secondes")
                            .font(.headline)
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(10)
                        
                        Text("Texte lu par \(SupabaseManager.shared.currentProfile) :")
                            .font(.subheadline).foregroundColor(.secondary)
                        
                        Text(item.details.text_read ?? "Texte non disponible")
                            .font(.title3)
                            .italic()
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(15)
                        
                        Divider()
                        
                        if let urlString = item.details.audio_url, let url = URL(string: urlString) {
                            Button(action: { toggleAudio(url: url) }) {
                                HStack {
                                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 60))
                                    Text(isPlaying ? "Pause" : "Écouter")
                                        .font(.title2).bold()
                                }
                                .foregroundColor(.blue)
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(20)
                            }
                        }
                    }
                    .padding()
                    
                } else {
                    // --- AFFICHAGE AUTRES JEUX ---
                    VStack(spacing: 25) {
                        Image(systemName: iconName(for: item.game_type))
                            .font(.system(size: 80))
                            .foregroundColor(.blue)
                        
                        if let summary = item.details.exercise_summary {
                            Text(summary)
                                .font(.title2)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                                .padding()
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(15)
                        }
                        
                        HStack(spacing: 40) {
                            StatBox(label: "Réussis", value: "\(item.details.score ?? 0)", color: .green)
                            StatBox(label: "Fautes", value: "\(item.details.mistakes ?? 0)", color: .red)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Détail de l'exercice")
        .onDisappear {
            player?.pause()
            if let observer = playbackObserver {
                NotificationCenter.default.removeObserver(observer)
                playbackObserver = nil
            }
        }
    }
    
    // --- GESTION AUDIO CORRIGÉE ---
    func toggleAudio(url: URL) {
        // IMPORTANT : Forcer la session audio sur le haut-parleur
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: .defaultToSpeaker)
            try session.setActive(true)
        } catch { print("Erreur Audio Session: \(error)") }
        
        if player == nil {
            player = AVPlayer(url: url)
        }
        
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            player?.play()
            isPlaying = true

            // Auto-reset à la fin (on supprime l'ancien observer avant d'en ajouter un nouveau)
            if let observer = playbackObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            playbackObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem, queue: .main) { _ in
                self.isPlaying = false
                self.player?.seek(to: .zero)
            }
        }
    }
    
    func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            displayFormatter.locale = Locale(identifier: "fr_FR")
            return displayFormatter.string(from: date)
        }
        return isoString
    }
    
    func iconName(for type: String) -> String {
        switch type.lowercased() {
        case "math": return "number.circle.fill"
        case "quiz": return "pencil.and.scribble"
        case "write": return "keyboard.fill"
        default: return "star.fill"
        }
    }
}

// Petit composant pour les boites de stats
struct StatBox: View {
    let label: String
    let value: String
    let color: Color
    var body: some View {
        VStack {
            Text(value).font(.largeTitle).bold().foregroundColor(color)
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .frame(width: 100, height: 100)
        .background(color.opacity(0.05))
        .cornerRadius(15)
    }
}
