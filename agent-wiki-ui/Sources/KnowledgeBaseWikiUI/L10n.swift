import Foundation
import LocalizationKit

/// Wiki UI 사용자 노출 문자열 키. `CaseIterable` 이라 누락 검증이 전 키를 순회할 수 있다.
enum L10nKey: String, CaseIterable {
    case ActivityViewsEmptyTitle = "ActivityViews.empty_title"
    case ActivityViewsEmptyDescription = "ActivityViews.empty_description"
    case AgentDefinitionViewEmptyTitle = "AgentDefinitionView.empty_title"
    case AgentDefinitionViewEmptyDescription = "AgentDefinitionView.empty_description"
    case LedgerDetailPaneEmptyPickLedger = "LedgerDetailPane.empty_pick_ledger"
    case LedgerDetailPaneEmptyPickEvidence = "LedgerDetailPane.empty_pick_evidence"
    case LedgerDetailPaneEmptyPickEvidenceDesc = "LedgerDetailPane.empty_pick_evidence_desc"
    case LedgerDetailPaneEmptySettingsTitle = "LedgerDetailPane.empty_settings_title"
    case LedgerDetailPaneEmptySettingsDesc = "LedgerDetailPane.empty_settings_desc"
    case LedgerDetailPaneEmptySettingsOpen = "LedgerDetailPane.empty_settings_open"
    case LedgerDetailPaneEmptyPickTrash = "LedgerDetailPane.empty_pick_trash"
    case LedgerDetailPaneEmptyPickTrashDesc = "LedgerDetailPane.empty_pick_trash_desc"
    case LedgerDetailPaneEmptyPickWiki = "LedgerDetailPane.empty_pick_wiki"
    case LedgerDetailPaneEmptyPickWikiDesc = "LedgerDetailPane.empty_pick_wiki_desc"
    case LedgerDetailPaneEmptyPickAgent = "LedgerDetailPane.empty_pick_agent"
    case LedgerDetailPaneEmptyPickAgentDesc = "LedgerDetailPane.empty_pick_agent_desc"
    case LedgerDetailPaneEmptyEventsTitle = "LedgerDetailPane.empty_events_title"
    case LedgerDetailPaneEmptyEventsDesc = "LedgerDetailPane.empty_events_desc"
    case LedgerDetailPaneEmptyChangesTitle = "LedgerDetailPane.empty_changes_title"
    case LedgerDetailPaneEmptyChangesDesc = "LedgerDetailPane.empty_changes_desc"
    case LedgerDetailPaneEmptyDiscussTitle = "LedgerDetailPane.empty_discuss_title"
    case LedgerDetailPaneEmptyDiscussDesc = "LedgerDetailPane.empty_discuss_desc"
    case LedgerDetailPaneEmptyLearningTitle = "LedgerDetailPane.empty_learning_title"
    case LedgerDetailPaneEmptyLearningDesc = "LedgerDetailPane.empty_learning_desc"
    case LedgerDetailPaneEmptyPickNote = "LedgerDetailPane.empty_pick_note"
    case LedgerDetailPaneEmptyPickNoteDesc = "LedgerDetailPane.empty_pick_note_desc"
    case DepthViewsEmptyInboxTitle = "DepthViews.empty_inbox_title"
    case DepthViewsEmptyInboxDesc = "DepthViews.empty_inbox_desc"
    case DepthViewsEmptyReviewTitle = "DepthViews.empty_review_title"
    case DepthViewsEmptyReviewDesc = "DepthViews.empty_review_desc"
    case EvidenceViewsEmptyTitle = "EvidenceViews.empty_title"
    case EvidenceViewsEmptyDescription = "EvidenceViews.empty_description"
    case DiscussionsViewEmptyTitle = "DiscussionsView.empty_title"
    case DiscussionsViewEmptyDescription = "DiscussionsView.empty_description"
    case EventsTimelineViewEmptyTitle = "EventsTimelineView.empty_title"
    case EventsTimelineViewEmptyDescription = "EventsTimelineView.empty_description"
    case EventsTimelineViewEmptyPreviewTitle = "EventsTimelineView.empty_preview_title"
    case EventsTimelineViewEmptyPreviewDesc = "EventsTimelineView.empty_preview_desc"
    case EventsTimelineViewEmptyBlobTitle = "EventsTimelineView.empty_blob_title"
    case EventsTimelineViewEmptyBlobDesc = "EventsTimelineView.empty_blob_desc"
    case PromotionQueueViewEmptyTitle = "PromotionQueueView.empty_title"
    case PromotionQueueViewEmptyDescription = "PromotionQueueView.empty_description"
    case LedgerContentColumnEmptyWikiTitle = "LedgerContentColumn.empty_wiki_title"
    case LedgerContentColumnEmptyWikiDesc = "LedgerContentColumn.empty_wiki_desc"
    case LedgerContentColumnEmptyTrashTitle = "LedgerContentColumn.empty_trash_title"
    case LedgerContentColumnEmptyTrashDesc = "LedgerContentColumn.empty_trash_desc"
    case LedgerContentColumnEmptyNotesDeleted = "LedgerContentColumn.empty_notes_deleted"
    case LedgerContentColumnEmptyNotes = "LedgerContentColumn.empty_notes"
    case LedgerContentColumnEmptyNotesDesc = "LedgerContentColumn.empty_notes_desc"
    case RepositoryTasksViewEmptyNotRepoTitle = "RepositoryTasksView.empty_not_repo_title"
    case RepositoryTasksViewEmptyNotRepoDesc = "RepositoryTasksView.empty_not_repo_desc"
    case RepositoryTasksViewEmptyNoTasksTitle = "RepositoryTasksView.empty_no_tasks_title"
    case RepositoryTasksViewEmptyNoTasksDesc = "RepositoryTasksView.empty_no_tasks_desc"
    case RepositoryTasksViewEmptyPickTaskTitle = "RepositoryTasksView.empty_pick_task_title"
    case RepositoryTasksViewEmptyPickTaskDesc = "RepositoryTasksView.empty_pick_task_desc"
    case RepositoryTasksViewEmptyNoRoleTitle = "RepositoryTasksView.empty_no_role_title"
    case RepositoryTasksViewEmptyNoRoleDesc = "RepositoryTasksView.empty_no_role_desc"
    case RepositoryTasksViewEmptyNoRoleAction = "RepositoryTasksView.empty_no_role_action"
    case RecentChangesViewEmptyTitle = "RecentChangesView.empty_title"
    case RecentChangesViewEmptyDescription = "RecentChangesView.empty_description"
    case RecentChangesViewEmptyDiffTitle = "RecentChangesView.empty_diff_title"
    case RecentChangesViewEmptyDiffDescription = "RecentChangesView.empty_diff_description"
    case StructureViewMeasuring = "StructureView.measuring"
    case StructureViewEmptyTitle = "StructureView.empty_title"
    case StructureViewEmptyDescription = "StructureView.empty_description"
    case LearningViewEmptyTitle = "LearningView.empty_title"
    case LearningViewEmptyDescription = "LearningView.empty_description"
    case LedgerViewEmptyRootTitle = "LedgerView.empty_root_title"
    case LedgerViewEmptyRootDesc = "LedgerView.empty_root_desc"
    case LedgerViewEmptyRootAction = "LedgerView.empty_root_action"
}

@MainActor
enum L10n {
    static let manager = LocalizationManager(
        baseBundle: ResourceBundle.localization(preferredName: "AgentWikiUI_KnowledgeBaseWikiUI")
    )
}

@MainActor
func L(_ key: L10nKey) -> String { L10n.manager.string(key.rawValue) }

@MainActor
func L(_ key: L10nKey, _ args: CVarArg...) -> String {
    String(format: L10n.manager.string(key.rawValue), locale: .current, arguments: args)
}
