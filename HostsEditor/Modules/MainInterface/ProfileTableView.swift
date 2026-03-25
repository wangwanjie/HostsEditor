import Cocoa

protocol ProfileTableViewContextMenuDelegate: AnyObject {
    func tableView(_ tableView: ProfileTableView, menuForRow row: Int) -> NSMenu?
}

final class ProfileTableView: NSTableView {
    weak var contextMenuDelegate: ProfileTableViewContextMenuDelegate?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        guard row >= 0 else { return nil }
        return contextMenuDelegate?.tableView(self, menuForRow: row)
    }
}
