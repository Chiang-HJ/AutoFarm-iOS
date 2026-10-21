import SwiftUI
import CoreLocation

public struct RouteEditorView: View {
    @ObservedObject var db = SavedDatabaseStore.shared
    @ObservedObject var session = AutoFarmSession.shared
    @Environment(\.dismiss) var dismiss

    var initialRoute: SavedRoute

    @State private var routeName: String
    @State private var routeTag: String
    @State private var routeNote: String
    @State private var nodes: [RouteNode]

    // 新增點位 Sheet
    @State private var isAddNodePresented: Bool = false
    @State private var newLatStr: String = ""
    @State private var newLngStr: String = ""
    @State private var newWaitSec: Int = 0
    @State private var newLabelStr: String = ""

    // 編輯單一點位 Sheet
    @State private var editingNodeIndex: Int? = nil
    @State private var editLatStr: String = ""
    @State private var editLngStr: String = ""
    @State private var editWaitSec: Int = 0
    @State private var editLabelStr: String = ""

    public init(route: SavedRoute) {
        self.initialRoute = route
        _routeName = State(initialValue: route.name)
        _routeTag = State(initialValue: route.tag)
        _routeNote = State(initialValue: route.note)
        _nodes = State(initialValue: route.nodes)
    }

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 路線基本資訊設定區
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("路線名稱", text: $routeName)
                            .font(.system(size: 15, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(8)

                        TextField("標籤 (可選)", text: $routeTag)
                            .font(.system(size: 13))
                            .frame(width: 90)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(8)
                    }

                    TextField("備忘筆記 (可選)", text: $routeNote)
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(UIColor.systemBackground))

                Divider()

                // 快捷動作工具列: 點位統計、加入目前位置、手動新增點位
                HStack(spacing: 10) {
                    Text("航點清單 (\(nodes.count) 點)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.secondary)

                    Spacer()

                    // 加入目前定位
                    Button(action: addCurrentLocationAsNode) {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                            Text("加目前位置")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(6)
                    }

                    // 手動輸入新航點
                    Button(action: {
                        newLatStr = String(format: "%.6f", session.currentLat)
                        newLngStr = String(format: "%.6f", session.currentLng)
                        newWaitSec = 0
                        newLabelStr = ""
                        isAddNodePresented = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("手動新增")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(6)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(UIColor.secondarySystemBackground).opacity(0.5))

                // 航點列表 (支援拖曳重排與滑動刪除)
                if nodes.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "map")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("目前路線尚無任何航點\n請點擊上方按鈕新增點位")
                            .font(.system(size: 13))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(nodes.indices, id: \.self) { idx in
                            let node = nodes[idx]
                            HStack(spacing: 10) {
                                // 序號球
                                ZStack {
                                    Circle()
                                        .fill(Color.blue.opacity(0.15))
                                        .frame(width: 28, height: 28)
                                    Text("\(idx + 1)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.blue)
                                }

                                // 點位資訊
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text("\(String(format: "%.6f", node.lat)), \(String(format: "%.6f", node.lng))")
                                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.primary)

                                        if let lbl = node.label, !lbl.isEmpty {
                                            Text(lbl)
                                                .font(.system(size: 10))
                                                .foregroundColor(.purple)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.purple.opacity(0.12))
                                                .cornerRadius(3)
                                        }
                                    }

                                    HStack(spacing: 12) {
                                        Text("停留等待: \(node.waitTimeSec) 秒")
                                            .font(.system(size: 11))
                                            .foregroundColor(node.waitTimeSec > 0 ? .orange : .secondary)

                                        if idx > 0 {
                                            let prev = nodes[idx - 1]
                                            let dist = EngineMath.haversineDistance(lat1: prev.lat, lon1: prev.lng, lat2: node.lat, lon2: node.lng)
                                            Text("距前點: \(Int(dist))m")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }

                                Spacer()

                                // 瞬移到此點
                                Button(action: {
                                    session.teleport(to: node.lat, lng: node.lng, label: "航點 #\(idx + 1)")
                                }) {
                                    Image(systemName: "location.north.circle")
                                        .font(.system(size: 16))
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(BorderlessButtonStyle())

                                // 編輯此點
                                Button(action: {
                                    editingNodeIndex = idx
                                    editLatStr = String(format: "%.6f", node.lat)
                                    editLngStr = String(format: "%.6f", node.lng)
                                    editWaitSec = node.waitTimeSec
                                    editLabelStr = node.label ?? ""
                                }) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 15))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(BorderlessButtonStyle())

                                // 刪除此點
                                Button(action: {
                                    nodes.remove(at: idx)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 15))
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete { indexSet in
                            nodes.remove(atOffsets: indexSet)
                        }
                        .onMove { indices, newOffset in
                            nodes.move(fromOffsets: indices, toOffset: newOffset)
                        }
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, .constant(.active))
                }
            }
            .navigationTitle("編輯路線點位")
            .navigationBarItems(
                leading: Button("取消") { dismiss() },
                trailing: Button("儲存變更") {
                    saveChanges()
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.blue)
            )
            .sheet(isPresented: $isAddNodePresented) {
                addNodeSheet
            }
            .sheet(isPresented: Binding(
                get: { editingNodeIndex != nil },
                set: { if !$0 { editingNodeIndex = nil } }
            )) {
                editNodeSheet
            }
        }
    }

    // MARK: - 新增目前定位為航點
    private func addCurrentLocationAsNode() {
        let node = RouteNode(
            lat: session.currentLat,
            lng: session.currentLng,
            waitTimeSec: 0,
            label: "航點 #\(nodes.count + 1)"
        )
        nodes.append(node)
        session.toastMessage = "已加入目前位置航點！"
    }

    // MARK: - 儲存所有變更
    private func saveChanges() {
        guard !nodes.isEmpty else {
            session.toastMessage = "路線不能為空，請至少保留 1 個航點！"
            return
        }
        db.updateRoute(
            id: initialRoute.id,
            name: routeName,
            nodes: nodes,
            tag: routeTag,
            note: routeNote
        )
        session.toastMessage = "路線 [\(routeName)] 點位已成功儲存！"
        dismiss()
    }

    // MARK: - 手動新增航點彈窗
    private var addNodeSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("經緯度座標")) {
                    TextField("緯度 (Latitude)", text: $newLatStr)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("經度 (Longitude)", text: $newLngStr)
                        .keyboardType(.numbersAndPunctuation)
                }

                Section(header: Text("點位設定")) {
                    Stepper("停留等待: \(newWaitSec) 秒", value: $newWaitSec, in: 0...300)
                    TextField("航點標籤 (可選)", text: $newLabelStr)
                }

                Section {
                    Button("加入航點") {
                        if let lat = Double(newLatStr.trimmingCharacters(in: .whitespacesAndNewlines)),
                           let lng = Double(newLngStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            let node = RouteNode(
                                lat: lat,
                                lng: lng,
                                waitTimeSec: newWaitSec,
                                label: newLabelStr.isEmpty ? nil : newLabelStr
                            )
                            nodes.append(node)
                            isAddNodePresented = false
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("手動新增航點")
            .navigationBarItems(leading: Button("關閉") { isAddNodePresented = false })
        }
    }

    // MARK: - 編輯單一航點彈窗
    private var editNodeSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("經緯度座標")) {
                    TextField("緯度 (Latitude)", text: $editLatStr)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("經度 (Longitude)", text: $editLngStr)
                        .keyboardType(.numbersAndPunctuation)
                }

                Section(header: Text("點位設定")) {
                    Stepper("停留等待: \(editWaitSec) 秒", value: $editWaitSec, in: 0...300)
                    TextField("航點標籤 (可選)", text: $editLabelStr)
                }

                Section {
                    Button("確認修改") {
                        if let idx = editingNodeIndex,
                           let lat = Double(editLatStr.trimmingCharacters(in: .whitespacesAndNewlines)),
                           let lng = Double(editLngStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            nodes[idx].lat = lat
                            nodes[idx].lng = lng
                            nodes[idx].waitTimeSec = editWaitSec
                            nodes[idx].label = editLabelStr.isEmpty ? nil : editLabelStr
                            editingNodeIndex = nil
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("編輯航點")
            .navigationBarItems(leading: Button("取消") { editingNodeIndex = nil })
        }
    }
}
