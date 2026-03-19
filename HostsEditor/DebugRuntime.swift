import Foundation

#if VIEW_SCOPE_ENABLED
import ViewScopeServer
#endif

enum DebugRuntime {
    static var isViewScopeEnabled: Bool {
        #if VIEW_SCOPE_ENABLED
        true
        #else
        false
        #endif
    }

    static func start() {
        #if VIEW_SCOPE_ENABLED
        ViewScopeInspector.start()
        #endif
    }
}
