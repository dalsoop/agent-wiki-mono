#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

void FleetDeskActivationHookForceLink(void);
void FleetDeskInstallActivationHook(void);
bool FleetDeskShouldForceAccessory(void);

#ifdef __cplusplus
}
#endif
