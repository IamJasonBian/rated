import SwiftUI

/// Pairwise binary-search ranker (RankScreen.jsx). Head-to-head picks bisect
/// the user's list; on save the Elo map, order, pairwise outcomes and final
/// score are committed through AppStore.
struct RankView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let movie: Movie
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .animation(spring, value: session?.pending?.chosen)
        .animation(spring, value: session?.lo)
        .animation(spring, value: session?.isDone)
    }

    private var spring: Animation? { reduceMotion ? nil : .spring(duration: 0.35) }

    private func header(_ title: String, cancel: String) -> some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(W.text)
            Spacer()
            Button(cancel) { store.rankTarget = nil }
                .font(.subheadline).foregroundStyle(W.dim)
                .hitArea()
                .accessibilityIdentifier("rank-cancel")
        }
        .padding(.horizontal, 22).padding(.vertical, 10)
    }

    private func find(_ id: String) -> Movie { id == movie.id ? movie : (Catalog.shared.find(id) ?? movie) }

    @ViewBuilder
    private func compareView(_ s: RankSession) -> some View {
        header("Rank It", cancel: "Cancel")
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    PosterView(url: movie.posterURL, title: movie.title, width: 40, height: 56, radius: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(movie.title).font(.headline).foregroundStyle(W.text)
                    }
                    Spacer()
                }
                .card(radius: 14, fill: W.accent.opacity(0.06), stroke: W.accent.opacity(0.25), padding: 12)

                Text("Which do you prefer?").font(.subheadline).foregroundStyle(W.dim)

                if let p = s.pending {
                    resultCard(find(p.chosen), chosen: true)
                    resultCard(find(p.other), chosen: false)
                    RatedButton(title: s.willFinishOnAdvance ? "Finish Ranking" : "Next Comparison") {
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
                Text(m.title).font(.subheadline.weight(.semibold)).foregroundStyle(W.text).multilineTextAlignment(.center).lineLimit(2)
                Text("This One").font(.subheadline.weight(.semibold)).foregroundStyle(W.accent)
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10).fill(W.accentDim))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(W.accent.opacity(0.3)))
            }
            .frame(maxWidth: .infinity)
            .card(radius: 14, padding: 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pick \(m.title) over \(opponent.title)")
        .accessibilityIdentifier(isNew ? "rank-pick-new" : "rank-pick-existing")
    }

    private func resultCard(_ m: Movie, chosen: Bool) -> some View {
        HStack(spacing: 12) {
            PosterView(url: m.posterURL, title: m.title, width: 48, height: 66, radius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(chosen ? "You Preferred" : "Not This Time").font(.subheadline.weight(.semibold)).foregroundStyle(chosen ? W.green : W.dim)
                Text(m.title).font(.headline).foregroundStyle(W.text)
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
        header("Ranked", cancel: "Close")
        ScrollView {
            VStack(spacing: 5) {
                VStack(spacing: 6) {
                    Text("\(movie.title) added!").font(.headline).foregroundStyle(W.gold)
                    Text("Landed at #\(pos + 1)").font(.subheadline).foregroundStyle(W.dim)
                        .accessibilityIdentifier("rank-landed")
                }
                .padding(.vertical, 14)
                ForEach(Array(ids.enumerated()), id: \.element) { i, id in
                    let m = find(id)
                    let isNew = id == movie.id
                    HStack(spacing: 10) {
                        Text(verbatim: Medal.label(i)).font(.subheadline.weight(.semibold)).foregroundStyle(W.dim).frame(minWidth: 24)
                        PosterView(url: m.posterURL, title: m.title, width: 28, height: 38, radius: 4)
                        Text(m.title).font(.headline).foregroundStyle(isNew ? W.accent : W.text).lineLimit(1)
                        Spacer()
                        if isNew { BadgeView(text: "New") }
                        Text(verbatim: "\(s.elo[id] ?? 1500)").font(.subheadline.weight(.semibold)).foregroundStyle(W.blue)
                    }
                    .card(radius: 12, fill: isNew ? W.accentDim : i == 0 ? W.goldDim : W.card,
                          stroke: isNew ? W.accent.opacity(0.4) : W.border, padding: 8)
                }
                RatedButton(title: "Save to Profile") { store.completeRank(s, movie: movie) }
                    .padding(.top, 10)
                    .accessibilityIdentifier("rank-save")
            }
            .padding(.horizontal, 22).padding(.bottom, 20)
        }
    }
}
