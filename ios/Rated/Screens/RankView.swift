import SwiftUI

/// Pairwise binary-search ranker (RankScreen.jsx). Head-to-head picks bisect
/// the user's list; on save the Elo map, order, pairwise outcomes and final
/// score are committed through AppStore.
struct RankView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let movie: Movie
    @State private var session: RankSession?

    var body: some View {
        VStack(spacing: 0) {
            if let s = session {
                if s.isDone { doneView(s) } else { compareView(s) }
            }
        }
        .background(W.bg.ignoresSafeArea())
        .onAppear {
            if session == nil { session = RankSession(newId: movie.id, rankedIds: store.rankedIds, elo: store.eloScores) }
        }
        .animation(.spring(duration: 0.35), value: session?.pending?.chosen)
        .animation(.spring(duration: 0.35), value: session?.lo)
        .animation(.spring(duration: 0.35), value: session?.isDone)
    }

    private func header(_ title: String, cancel: String) -> some View {
        HStack {
            Text(title).mono(14, .heavy).foregroundStyle(W.text)
            Spacer()
            Button(cancel) { store.rankTarget = nil }
                .mono(11).foregroundStyle(W.dim)
                .accessibilityIdentifier("rank-cancel")
        }
        .padding(.horizontal, 22).padding(.vertical, 10)
    }

    private func find(_ id: String) -> Movie { id == movie.id ? movie : (Catalog.shared.find(id) ?? movie) }

    @ViewBuilder
    private func compareView(_ s: RankSession) -> some View {
        header("⚡ RANK IT", cancel: "✕ Cancel")
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    PosterView(url: movie.posterURL, title: movie.title, width: 40, height: 56, radius: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PLACING IN YOUR LIST").mono(8, .bold).tracking(1).foregroundStyle(W.accent)
                        Text(movie.title).mono(14, .black).foregroundStyle(W.text)
                        Text([movie.releaseYear.map(String.init), movie.directors.first].compactMap { $0 }.joined(separator: " · "))
                            .mono(9).foregroundStyle(W.dim)
                    }
                    Spacer()
                }
                .card(radius: 14, fill: W.accent.opacity(0.06), stroke: W.accent.opacity(0.25), padding: 12)

                VStack(spacing: 2) {
                    Text("WHICH DO YOU PREFER?").mono(10).tracking(1).foregroundStyle(W.dim)
                    Text("~\(s.estimatedTotal) comparisons · \(s.remaining) remaining").mono(8).foregroundStyle(W.dim)
                }

                if let p = s.pending {
                    resultCard(find(p.chosen), chosen: true)
                    resultCard(find(p.other), chosen: false)
                    RatedButton(title: s.willFinishOnAdvance ? "FINISH RANKING →" : "NEXT COMPARISON →") {
                        Haptics.light()
                        session?.advance()
                    }
                    .accessibilityIdentifier("rank-next")
                } else if let oppId = s.opponentId {
                    let opp = find(oppId)
                    HStack(spacing: 10) {
                        pickCard(movie, isNew: true, opponent: opp, s: s)
                        pickCard(opp, isNew: false, opponent: movie, s: s)
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    ProgressView(value: s.progress).tint(W.accent).padding(.top, 4)
                }
            }
            .padding(.horizontal, 22)
        }
    }

    private func pickCard(_ m: Movie, isNew: Bool, opponent: Movie, s: RankSession) -> some View {
        Button {
            Haptics.medium()
            session?.pick(m.id)
        } label: {
            VStack(spacing: 8) {
                PosterView(url: m.posterURL, title: m.title, width: 110, height: 154, radius: 10)
                Text(m.title).mono(11, .heavy).foregroundStyle(W.text).multilineTextAlignment(.center).lineLimit(2)
                Text(m.releaseYear.map(String.init) ?? "").mono(9).foregroundStyle(W.dim)
                if isNew {
                    Text("NEW").mono(8, .bold).foregroundStyle(W.accent)
                } else {
                    Text("#\((store.rankedIds.firstIndex(of: m.id) ?? 0) + 1) in your list").mono(8, .bold).foregroundStyle(W.blue)
                }
                Text("THIS ONE ▶").mono(10, .black).foregroundStyle(W.accent)
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10).fill(W.accentDim))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(W.accent.opacity(0.3)))
            }
            .frame(maxWidth: .infinity)
            .card(radius: 16, padding: 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pick \(m.title) over \(opponent.title)")
        .accessibilityIdentifier(isNew ? "rank-pick-new" : "rank-pick-existing")
    }

    private func resultCard(_ m: Movie, chosen: Bool) -> some View {
        HStack(spacing: 12) {
            PosterView(url: m.posterURL, title: m.title, width: 48, height: 66, radius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(chosen ? "✓ YOU PREFERRED" : "✗ NOT THIS TIME").mono(8, .bold).tracking(1).foregroundStyle(chosen ? W.green : W.dim)
                Text(m.title).mono(14, .black).foregroundStyle(W.text)
                if chosen { Text("Narrowing down further…").mono(9).foregroundStyle(W.dim) }
            }
            Spacer()
        }
        .card(radius: 14, fill: chosen ? W.greenDim : W.card, stroke: chosen ? W.green.opacity(0.3) : W.border, padding: 14)
        .opacity(chosen ? 1 : 0.6)
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    @ViewBuilder
    private func doneView(_ s: RankSession) -> some View {
        let ids = s.finalIds
        let pos = (ids.firstIndex(of: movie.id) ?? 0)
        header("⚡ RANKED!", cancel: "✕")
        ScrollView {
            VStack(spacing: 5) {
                VStack(spacing: 6) {
                    T("🏆").font(.system(size: 34))
                    Text("\(movie.title) added!").mono(14, .black).foregroundStyle(W.gold)
                    Text("Landed at #\(pos + 1)").mono(10).foregroundStyle(W.dim)
                        .accessibilityIdentifier("rank-landed")
                }
                .padding(.vertical, 14)
                SectionLabel(text: "YOUR UPDATED RANKINGS").padding(.bottom, 4)
                ForEach(Array(ids.enumerated()), id: \.element) { i, id in
                    let m = find(id)
                    let isNew = id == movie.id
                    HStack(spacing: 10) {
                        T(Medal.label(i)).mono(i < 3 ? 14 : 10, .black).foregroundStyle(W.dim).frame(width: 24)
                        PosterView(url: m.posterURL, title: m.title, width: 28, height: 38, radius: 4)
                        Text(m.title).mono(11, .bold).foregroundStyle(isNew ? W.accent : W.text).lineLimit(1)
                        Spacer()
                        if isNew { BadgeView(text: "NEW") }
                        T("\(s.elo[id] ?? 1500)").mono(9, .bold).foregroundStyle(W.blue)
                    }
                    .card(radius: 10, fill: isNew ? W.accentDim : i == 0 ? W.goldDim : W.card,
                          stroke: isNew ? W.accent.opacity(0.4) : W.border, padding: 8)
                }
                RatedButton(title: "SAVE TO PROFILE →") { store.completeRank(s, movie: movie) }
                    .padding(.top, 10)
                    .accessibilityIdentifier("rank-save")
            }
            .padding(.horizontal, 22).padding(.bottom, 20)
        }
    }
}
