#ifndef PACKAGES_FLUTTER_WEBRTC_LINUX_TASK_RUNNER_LINUX_H_
#define PACKAGES_FLUTTER_WEBRTC_LINUX_TASK_RUNNER_LINUX_H_

#include <functional>

using TaskClosure = std::function<void()>;

namespace livekit_client_plugin {

class TaskRunnerLinux {
 public:
  TaskRunnerLinux() = default;
  ~TaskRunnerLinux() = default;

  // Runs [task] on the main loop, after the ones enqueued before it.
  // ROOSTER: the runner holds nothing a task could outlive (see the .cc).
  void EnqueueTask(TaskClosure task);
};

}  // namespace livekit_client_plugin

#endif  // PACKAGES_FLUTTER_WEBRTC_LINUX_TASK_RUNNER_LINUX_H_