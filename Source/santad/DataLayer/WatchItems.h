/// Copyright 2022 Google LLC
///
/// Licensed under the Apache License, Version 2.0 (the "License");
/// you may not use this file except in compliance with the License.
/// You may obtain a copy of the License at
///
///     https://www.apache.org/licenses/LICENSE-2.0
///
/// Unless required by applicable law or agreed to in writing, software
/// distributed under the License is distributed on an "AS IS" BASIS,
/// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
/// See the License for the specific language governing permissions and
/// limitations under the License.

#ifndef SANTA__SANTAD__DATALAYER_WATCHITEMS_H
#define SANTA__SANTAD__DATALAYER_WATCHITEMS_H

#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <utility>

#include <memory>
#include <set>
#include <string>
#include <vector>

#include "Source/common/PrefixTree.h"

extern const NSString *kWatchItemConfigKeyPath;
extern const NSString *kWatchItemConfigKeyWriteOnly;
extern const NSString *kWatchItemConfigKeyIsPrefix;
extern const NSString *kWatchItemConfigKeyAuditOnly;
extern const NSString *kWatchItemConfigKeyAllowedBinaryPaths;
extern const NSString *kWatchItemConfigKeyAllowedCertificatesSha256;
extern const NSString *kWatchItemConfigKeyAllowedTeamIDs;
extern const NSString *kWatchItemConfigKeyAllowedCDHashes;

// Forward declarations
namespace santa::santad::data_layer {
class WatchItemsPeer;
}

namespace santa::santad::data_layer {

struct WatchItemPolicy {
  WatchItemPolicy(std::string_view n, std::string_view p, bool wo = false, bool ip = false,
                  bool ao = true, std::set<std::string> &&abp = {},
                  std::set<std::string> &&acs = {}, std::set<std::string> &&ati = {},
                  std::set<std::string> &&ach = {});

  std::string name;
  std::string path;
  bool write_only;
  bool is_prefix;
  bool audit_only;
  std::set<std::string> allowed_binary_paths;
  std::set<std::string> allowed_certificates_sha256;
  std::set<std::string> allowed_team_ids;
  std::set<std::string> allowed_cdhashes;
};

class WatchItems : public std::enable_shared_from_this<WatchItems> {
 public:
  using WatchItemsTree = santa::common::PrefixTree<std::shared_ptr<WatchItemPolicy>>;

  // Factory
  std::shared_ptr<WatchItems> Create(NSString *config_path, uint64_t reapply_config_frequency_secs);

  WatchItems(NSString *config_path_, dispatch_source_t timer_source,
             void (^periodic_task_complete_f)(void) = nullptr);
  ~WatchItems();

  void BeginPeriodicTask();

  std::optional<std::shared_ptr<WatchItemPolicy>> FindPolicyForPath(const char *input);

  friend class santa::santad::data_layer::WatchItemsPeer;

 private:
  void ReloadConfig(NSDictionary *new_config);
  bool SetCurrentConfig(std::unique_ptr<WatchItemsTree> new_tree,
                        std::set<std::string> &&new_monitored_paths, NSDictionary *new_config);
  bool ParseConfig(NSDictionary *config, std::vector<std::shared_ptr<WatchItemPolicy>> &policies);
  bool BuildPolicyTree(const std::vector<std::shared_ptr<WatchItemPolicy>> &watch_items,
                       WatchItemsTree &tree, std::set<std::string> &paths);

  NSString *config_path_;
  dispatch_source_t timer_source_;
  void (^periodic_task_complete_f_)(void);
  std::unique_ptr<WatchItemsTree> watch_items_;
  NSDictionary *current_config_;
  std::set<std::string> currently_monitored_paths_;
  absl::Mutex lock_;
  bool periodic_task_started_ = false;
};

}  // namespace santa::santad::data_layer

#endif