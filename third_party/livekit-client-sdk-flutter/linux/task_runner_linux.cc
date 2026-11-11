#include "task_runner_linux.h"

#include <glib.h>

namespace livekit_client_plugin {

// ROOSTER: each task is handed to the main loop as its own callback, which
// owns it. The runner used to keep a queue and hand the loop a pointer to
// itself; a callback still waiting when the runner was destroyed (an audio
// visualizer stopped as a call is hung up, with a level on its way from the
// audio thread) then locked a mutex in freed memory on the main thread, and
// the app froze for good: no frame, no timer, nothing logged.
void TaskRunnerLinux::EnqueueTask(TaskClosure task) {
  GMainContext* context = g_main_context_default();
  if (!context) {
    return;
  }
  g_main_context_invoke_full(
      context, G_PRIORITY_DEFAULT,
      [](gpointer user_data) -> gboolean {
        (*static_cast<TaskClosure*>(user_data))();
        return G_SOURCE_REMOVE;
      },
      new TaskClosure(std::move(task)),
      [](gpointer user_data) { delete static_cast<TaskClosure*>(user_data); });
}

}  // namespace livekit_client_plugin
