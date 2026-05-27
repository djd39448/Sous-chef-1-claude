import Foundation

// ImagePoller — a small helper that polls /api/kitchen/week/{weekStart}
// while the backend is generating images in the background.
//
// Depends on:     APIClient, WeekResponse, MealPlanWithDays.
// Depended on by: HomeScreen, PlanScreen, ChatScreen — every surface
//                 that triggers a plan create or regenerate.
// Why it exists:  the backend creates meal-plan rows synchronously but
//                 fires image generation in goroutines (see
//                 backend/internal/api/images.go). Each image takes a
//                 few seconds. Rather than blocking the create call,
//                 the iOS client re-fetches the week on a short cadence
//                 until every day has an `imageUrl`, swapping placeholder
//                 thumbnails for real photos as they land.

extension APIClient {
    /// Poll `/api/kitchen/week/{weekStart}` every 5s up to ~60s,
    /// yielding a fresh `MealPlanWithDays` on each iteration that
    /// returns a plan. Finishes early once every day has a non-empty
    /// `imageUrl`, when the iteration cap is hit, or when the
    /// enclosing Task is cancelled. Network errors during a poll are
    /// swallowed — the next interval retries.
    func pollForReadyImages(weekStart: String) -> AsyncStream<MealPlanWithDays> {
        AsyncStream { continuation in
            let task = Task {
                // 12 × 5s = 60s window. Images usually land in ~10–30s
                // total at gpt-image-1 quality:"low" with 7 concurrent
                // generations; the window has slack for the slow tail.
                for _ in 0..<12 {
                    do {
                        try await Task.sleep(for: .seconds(5))
                    } catch {
                        break
                    }
                    if Task.isCancelled { break }
                    do {
                        let resp: WeekResponse = try await self.get("/api/kitchen/week/\(weekStart)")
                        if let plan = resp.mealPlan {
                            continuation.yield(plan)
                            let ready = plan.days.allSatisfy {
                                guard let u = $0.imageUrl else { return false }
                                return !u.isEmpty
                            }
                            if ready { break }
                        }
                    } catch {
                        // network blip — try again on next tick
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
