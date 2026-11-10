import AppKit
import mSTICKCore

/// Rappels : un seul minuteur, réglé sur le prochain rappel (aucune surveillance en continu).
@MainActor
final class ReminderCenter {
    private let store: NoteStore
    private let fire: (UUID) -> Void
    private var timer: Timer?
    private var scheduledFor: Date?

    init(store: NoteStore, fire: @escaping (UUID) -> Void) { self.store = store; self.fire = fire }

    private func next() -> (id: UUID, reminder: NoteReminder)? {
        var best: (UUID, NoteReminder)?
        for n in store.notes where !n.archived {
            for r in n.reminders ?? [] where best == nil || r.date < best!.1.date { best = (n.id, r) }
        }
        return best
    }

    /// À rappeler après chaque changement de note : ne touche au minuteur que si le prochain rappel a changé.
    func reschedule() {
        guard Prefs.shared.reminders, let (_, r) = next() else { timer?.invalidate(); timer = nil; scheduledFor = nil; return }
        if scheduledFor == r.date, timer != nil { return }
        timer?.invalidate()
        scheduledFor = r.date
        timer = Timer.scheduledTimer(withTimeInterval: max(0.5, r.date.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fireDue() }
        }
        timer?.tolerance = 1
    }

    private func fireDue() {
        timer = nil; scheduledFor = nil
        let now = Date()
        for n in store.notes where !n.archived {
            let due = (n.reminders ?? []).filter { $0.date <= now.addingTimeInterval(1) }
            guard !due.isEmpty else { continue }
            store.update(n.id) { note in
                let rest = (note.reminders ?? []).filter { r in !due.contains(r) }
                note.reminders = rest.isEmpty ? nil : rest
                for r in due { note.body = note.body.replacingOccurrences(of: r.label, with: r.label.replacingOccurrences(of: "🔔", with: "✅")) }
            }
            NSSound(named: "Glass")?.play()
            fire(n.id)
        }
        reschedule()
    }
}
