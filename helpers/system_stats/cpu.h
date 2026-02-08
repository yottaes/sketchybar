#include <mach/mach.h>
#include <mach/processor_info.h>
#include <stdbool.h>
#include <unistd.h>
#include <stdio.h>

#define MAX_CORES 32

struct cpu {
  host_t host;
  mach_msg_type_number_t count;
  host_cpu_load_info_data_t load;
  host_cpu_load_info_data_t prev_load;
  bool has_prev_load;

  int user_load;
  int sys_load;
  int total_load;

  // Per-core tracking
  natural_t ncores;
  int core_loads[MAX_CORES];
  processor_cpu_load_info_t prev_core_info;
  mach_msg_type_number_t prev_core_count;
  bool has_prev_core_info;
};

static inline void cpu_init(struct cpu* cpu) {
  cpu->host = mach_host_self();
  cpu->count = HOST_CPU_LOAD_INFO_COUNT;
  cpu->has_prev_load = false;
  cpu->user_load = 0;
  cpu->sys_load = 0;
  cpu->total_load = 0;

  cpu->ncores = 0;
  memset(cpu->core_loads, 0, sizeof(cpu->core_loads));
  cpu->prev_core_info = NULL;
  cpu->prev_core_count = 0;
  cpu->has_prev_core_info = false;
}

static inline void cpu_update_cores(struct cpu* cpu) {
  natural_t ncores = 0;
  processor_cpu_load_info_t info = NULL;
  mach_msg_type_number_t info_count = 0;

  kern_return_t kr = host_processor_info(cpu->host,
                                          PROCESSOR_CPU_LOAD_INFO,
                                          &ncores,
                                          (processor_info_array_t*)&info,
                                          &info_count);
  if (kr != KERN_SUCCESS) {
    return;
  }

  if (ncores > MAX_CORES) ncores = MAX_CORES;
  cpu->ncores = ncores;

  if (cpu->has_prev_core_info && cpu->prev_core_info) {
    natural_t prev_n = cpu->prev_core_count / PROCESSOR_CPU_LOAD_INFO_COUNT;
    if (prev_n > ncores) prev_n = ncores;

    for (natural_t i = 0; i < prev_n; i++) {
      unsigned int delta_user = info[i].cpu_ticks[CPU_STATE_USER]
                                - cpu->prev_core_info[i].cpu_ticks[CPU_STATE_USER];
      unsigned int delta_sys  = info[i].cpu_ticks[CPU_STATE_SYSTEM]
                                - cpu->prev_core_info[i].cpu_ticks[CPU_STATE_SYSTEM];
      unsigned int delta_idle = info[i].cpu_ticks[CPU_STATE_IDLE]
                                - cpu->prev_core_info[i].cpu_ticks[CPU_STATE_IDLE];
      unsigned int delta_nice = info[i].cpu_ticks[CPU_STATE_NICE]
                                - cpu->prev_core_info[i].cpu_ticks[CPU_STATE_NICE];

      unsigned int total = delta_user + delta_sys + delta_idle + delta_nice;
      if (total > 0) {
        cpu->core_loads[i] = (int)((double)(delta_user + delta_sys) / (double)total * 100.0);
      } else {
        cpu->core_loads[i] = 0;
      }
    }
  }

  // Deallocate previous snapshot
  if (cpu->prev_core_info) {
    vm_deallocate(mach_task_self(),
                  (vm_address_t)cpu->prev_core_info,
                  cpu->prev_core_count * sizeof(integer_t));
  }

  // Store current as previous for next iteration
  cpu->prev_core_info = info;
  cpu->prev_core_count = info_count;
  cpu->has_prev_core_info = true;
}

static inline void cpu_update(struct cpu* cpu) {
  kern_return_t error = host_statistics(cpu->host,
                                        HOST_CPU_LOAD_INFO,
                                        (host_info_t)&cpu->load,
                                        &cpu->count                );

  if (error != KERN_SUCCESS) {
    printf("Error: Could not read cpu host statistics.\n");
    return;
  }

  if (cpu->has_prev_load) {
    uint32_t delta_user = cpu->load.cpu_ticks[CPU_STATE_USER]
                          - cpu->prev_load.cpu_ticks[CPU_STATE_USER];

    uint32_t delta_system = cpu->load.cpu_ticks[CPU_STATE_SYSTEM]
                            - cpu->prev_load.cpu_ticks[CPU_STATE_SYSTEM];

    uint32_t delta_idle = cpu->load.cpu_ticks[CPU_STATE_IDLE]
                          - cpu->prev_load.cpu_ticks[CPU_STATE_IDLE];

    cpu->user_load = (double)delta_user / (double)(delta_system
                                                     + delta_user
                                                     + delta_idle) * 100.0;

    cpu->sys_load = (double)delta_system / (double)(delta_system
                                                      + delta_user
                                                      + delta_idle) * 100.0;

    cpu->total_load = cpu->user_load + cpu->sys_load;
  }

  cpu->prev_load = cpu->load;
  cpu->has_prev_load = true;

  cpu_update_cores(cpu);
}
