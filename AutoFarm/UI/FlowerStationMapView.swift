import SwiftUI
import MapKit
import CoreLocation

// MARK: - 花田總覽互動地圖 (UIViewRepresentable)
public struct FlowerStationMapContainer: UIViewRepresentable {
    @ObservedObject var station = FlowerStationManager.shared
    @Binding var selectedPoint: FlowerStationPoint?
    var onSelectPoint: ((FlowerStationPoint) -> Void)?

    public init(selectedPoint: Binding<FlowerStationPoint?>, onSelectPoint: ((FlowerStationPoint) -> Void)? = nil) {
        self._selectedPoint = selectedPoint
        self.onSelectPoint = onSelectPoint
    }

    public func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsScale = true

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        mapView.addGestureRecognizer(tapGesture)

        // 初始預設視角：直接定位到孟買花田核心區域 (19.0542, 72.8450)
        let mumbaiCoord = CLLocationCoordinate2D(latitude: 19.0542, longitude: 72.8450)
        let region = MKCoordinateRegion(center: mumbaiCoord, latitudinalMeters: 18000, longitudinalMeters: 18000)
        mapView.setRegion(region, animated: false)

        return mapView
    }

    public func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        // 使用者要求：花田總覽只顯示印度的花田 ("印")
        let points = station.allPoints.filter { $0.name.hasPrefix("印") }
        if context.coordinator.cachedPointCount != points.count {
            context.coordinator.cachedPointCount = points.count

            mapView.removeOverlays(mapView.overlays)
            mapView.removeAnnotations(mapView.annotations)

            var newAnnotations: [StationBadgeAnnotation] = []
            var newOverlays: [MKOverlay] = []

            for p in points {
                guard let center = p.coordinate else { continue }

                // 1. 多邊形花田路線輪廓邊框 (Convex Hull / 收果路線)
                if let hull = p.hull, hull.count >= 3 {
                    let coords = hull.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                    let polygon = StationPolygon(coordinates: coords, count: coords.count, point: p, polygonCoordinates: coords)
                    newOverlays.append(polygon)
                } else {
                    let circle = StationCircle(center: center, radius: 45.0, point: p)
                    newOverlays.append(circle)
                }

                // 2. 標籤標註
                let anno = StationBadgeAnnotation(point: p, coordinate: center)
                newAnnotations.append(anno)
            }

            mapView.addOverlays(newOverlays)
            mapView.addAnnotations(newAnnotations)
        }

        // 若選中特定點位，地圖平滑置中
        if let sel = selectedPoint, let coord = sel.coordinate {
            if context.coordinator.lastSelectedId != sel.id {
                context.coordinator.lastSelectedId = sel.id
                let region = MKCoordinateRegion(center: coord, latitudinalMeters: 1200, longitudinalMeters: 1200)
                mapView.setRegion(region, animated: true)
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, MKMapViewDelegate {
        var parent: FlowerStationMapContainer
        var cachedPointCount: Int = -1
        var lastSelectedId: String = ""

        init(_ parent: FlowerStationMapContainer) {
            self.parent = parent
        }

        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let poly = overlay as? StationPolygon {
                let renderer = MKPolygonRenderer(polygon: poly)
                let isCooling = poly.point.isCounting
                renderer.fillColor = isCooling ? UIColor.systemRed.withAlphaComponent(0.20) : UIColor.systemGreen.withAlphaComponent(0.20)
                renderer.strokeColor = isCooling ? UIColor.systemRed : UIColor.systemGreen
                renderer.lineWidth = 2.8
                return renderer
            } else if let circle = overlay as? StationCircle {
                let renderer = MKCircleRenderer(circle: circle)
                let isCooling = circle.point.isCounting
                renderer.fillColor = isCooling ? UIColor.systemRed.withAlphaComponent(0.20) : UIColor.systemGreen.withAlphaComponent(0.20)
                renderer.strokeColor = isCooling ? UIColor.systemRed : UIColor.systemGreen
                renderer.lineWidth = 2.8
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let stationAnno = annotation as? StationBadgeAnnotation else { return nil }
            let id = "StationBadgeMarker"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
            if view == nil {
                view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view?.canShowCallout = false
            } else {
                view?.annotation = annotation
            }

            let isCooling = stationAnno.point.isCounting
            view?.markerTintColor = isCooling ? .systemRed : .systemGreen
            view?.glyphText = stationAnno.point.displayBadgeNumber
            view?.titleVisibility = .visible
            return view
        }

        public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let stationAnno = view.annotation as? StationBadgeAnnotation else { return }
            parent.selectedPoint = stationAnno.point
            parent.onSelectPoint?(stationAnno.point)
        }

        @objc public func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let tapLocation = gesture.location(in: mapView)
            let tapCoord = mapView.convert(tapLocation, toCoordinateFrom: mapView)
            let tapMapPoint = MKMapPoint(tapCoord)

            for overlay in mapView.overlays.reversed() {
                if let poly = overlay as? StationPolygon {
                    if poly.boundingMapRect.contains(tapMapPoint) && pointInPolygon(point: tapCoord, polygon: poly.polygonCoordinates) {
                        parent.selectedPoint = poly.point
                        parent.onSelectPoint?(poly.point)
                        return
                    }
                } else if let circle = overlay as? StationCircle {
                    let centerPoint = MKMapPoint(circle.coordinate)
                    let distance = centerPoint.distance(to: tapMapPoint)
                    if distance <= circle.radius {
                        parent.selectedPoint = circle.point
                        parent.onSelectPoint?(circle.point)
                        return
                    }
                }
            }
        }

        private func pointInPolygon(point: CLLocationCoordinate2D, polygon: [CLLocationCoordinate2D]) -> Bool {
            guard polygon.count >= 3 else { return false }
            var isInside = false
            var j = polygon.count - 1
            for i in 0..<polygon.count {
                if (polygon[i].longitude < point.longitude && polygon[j].longitude >= point.longitude ||
                    polygon[j].longitude < point.longitude && polygon[i].longitude >= point.longitude) {
                    if (polygon[i].latitude + (point.longitude - polygon[i].longitude) / (polygon[j].longitude - polygon[i].longitude) * (polygon[j].latitude - polygon[i].latitude) < point.latitude) {
                        isInside.toggle()
                    }
                }
                j = i
            }
            return isInside
        }
    }
}

// MARK: - 自定義地圖元素
public class StationPolygon: MKPolygon {
    public var point: FlowerStationPoint!
    public var polygonCoordinates: [CLLocationCoordinate2D] = []

    public convenience init(coordinates coords: UnsafePointer<CLLocationCoordinate2D>, count: Int, point: FlowerStationPoint, polygonCoordinates: [CLLocationCoordinate2D] = []) {
        self.init(coordinates: coords, count: count)
        self.point = point
        self.polygonCoordinates = polygonCoordinates
    }
}

public class StationCircle: MKCircle {
    public var point: FlowerStationPoint!
    public convenience init(center: CLLocationCoordinate2D, radius: CLLocationDistance, point: FlowerStationPoint) {
        self.init(center: center, radius: radius)
        self.point = point
    }
}

public class StationBadgeAnnotation: NSObject, MKAnnotation {
    public let point: FlowerStationPoint
    public let coordinate: CLLocationCoordinate2D
    public var title: String? { point.name }

    public init(point: FlowerStationPoint, coordinate: CLLocationCoordinate2D) {
        self.point = point
        self.coordinate = coordinate
    }
}

// MARK: - 花田總覽主視圖 (與觀測站網頁端 100% 對齊)
public struct FlowerStationMapView: View {
    @ObservedObject var station = FlowerStationManager.shared
    @ObservedObject var session = AutoFarmSession.shared
    @Environment(\.dismiss) var dismiss

    // 地圖收合/展開狀態 (對齊附圖中「展開花田總覽地圖」)
    @State private var isMapExpanded: Bool = true

    // 分頁過濾：0 = 空間待命, 1 = 冷卻中
    @State private var filterTab: Int = 0

    // 搜尋輸入框
    @State private var searchText: String = ""

    // 選取之花田 (點擊多邊形或卡片)
    @State private var selectedPoint: FlowerStationPoint? = nil

    // 卡位彈窗表單
    @State private var isSlottingSheetPresented: Bool = false
    @State private var slottingPoint: FlowerStationPoint? = nil
    @State private var inputNickname: String = ""
    @State private var inputRemark: String = ""
    @State private var selectedRouteName: String = ""
    @State private var isSubmittingSlot: Bool = false

    public init() {}

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 1. 搜尋欄位
                searchBarSection

                // 2. 「展開花田總覽地圖」摺疊按鈕 (對齊附圖，零 Emoji，使用 SF Symbols)
                mapAccordionToggleHeader

                // 3. 嵌入式地圖
                if isMapExpanded {
                    FlowerStationMapContainer(selectedPoint: $selectedPoint) { point in
                        if !point.isCounting {
                            self.slottingPoint = point
                            self.isSlottingSheetPresented = true
                        }
                    }
                    .frame(height: 240)
                    .transition(.opacity)
                }

                // 4. 「空間待命 ( N )」與「冷卻中 ( N )」分類標籤列 (對齊附圖)
                filterTabsBar

                // 5. 花田清單
                flowerListView
            }
            .navigationTitle("花田觀測站總覽")
            .navigationBarItems(
                leading: Button(action: { station.fetchFlowerPoints() }) {
                    Image(systemName: "arrow.clockwise")
                },
                trailing: Button("關閉") { dismiss() }
            )
            .sheet(isPresented: $isSlottingSheetPresented) {
                if let p = slottingPoint {
                    slotActionSheet(for: p)
                }
            }
            .onAppear {
                station.fetchFlowerPoints()
            }
        }
    }

    // MARK: - 搜尋欄位
    private var searchBarSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("輸入花田名稱或苗數 (如 #10)", text: $searchText)
                .font(.system(size: 14))
                .autocapitalization(.none)
                .disableAutocorrection(true)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - 地圖收合/展開標題列 (對齊附圖)
    private var mapAccordionToggleHeader: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isMapExpanded.toggle()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: isMapExpanded ? "map.fill" : "map")
                    .foregroundColor(.blue)
                    .font(.system(size: 15))

                Text(isMapExpanded ? "收合花田總覽地圖" : "展開花田總覽地圖")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.blue)

                Spacer()

                Image(systemName: isMapExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.blue.opacity(0.08))
            .cornerRadius(10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - 空間待命 / 冷卻中 頁籤列 (對齊附圖，僅統計印度花田，已卡位者不計入待命)
    private var filterTabsBar: some View {
        let indiaPoints = station.allPoints.filter { $0.name.hasPrefix("印") }
        let idleCount = indiaPoints.filter { !$0.isCounting && $0.occupierUid == nil && $0.planter.isEmpty && !$0.isHidden }.count
        let coolingCount = indiaPoints.filter { $0.isCounting }.count

        return HStack(spacing: 12) {
            // 空間待命按鈕
            Button(action: { filterTab = 0 }) {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle")
                        .foregroundColor(filterTab == 0 ? .blue : .secondary)
                    Text("空間待命 ( \(idleCount) )")
                        .font(.system(size: 14, weight: filterTab == 0 ? .bold : .medium))
                        .foregroundColor(filterTab == 0 ? .blue : .primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(filterTab == 0 ? Color.blue.opacity(0.12) : Color(UIColor.secondarySystemBackground))
                .cornerRadius(10)
            }

            // 冷卻中按鈕
            Button(action: { filterTab = 1 }) {
                HStack(spacing: 6) {
                    Image(systemName: "hourglass")
                        .foregroundColor(filterTab == 1 ? .red : .secondary)
                    Text("冷卻中 ( \(coolingCount) )")
                        .font(.system(size: 14, weight: filterTab == 1 ? .bold : .medium))
                        .foregroundColor(filterTab == 1 ? .red : .primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(filterTab == 1 ? Color.red.opacity(0.12) : Color(UIColor.secondarySystemBackground))
                .cornerRadius(10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - 花田清單 (使用者要求：僅顯示印度花田，空間待命排除被卡位花田)
    private var filteredPoints: [FlowerStationPoint] {
        var list = station.allPoints.filter { $0.name.hasPrefix("印") }
        if filterTab == 0 {
            // 空間待命：必須為非計時中，且未被任何人卡位
            list = list.filter { !$0.isCounting && $0.occupierUid == nil && $0.planter.isEmpty && !$0.isHidden }
        } else {
            list = list.filter { $0.isCounting }
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            if q.hasPrefix("#") {
                let numStr = String(q.dropFirst())
                if let targetSeeds = Int(numStr) {
                    list = list.filter { ($0.seedlings ?? 0) >= targetSeeds }
                }
            } else {
                list = list.filter {
                    $0.name.lowercased().contains(q) ||
                    $0.remark.lowercased().contains(q) ||
                    $0.planter.lowercased().contains(q) ||
                    $0.displayBadgeNumber.lowercased().contains(q)
                }
            }
        }
        return list
    }

    private var flowerListView: some View {
        List {
            ForEach(filteredPoints) { point in
                flowerCardRow(for: point)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        self.selectedPoint = point
                        // 冷卻中的花田不需要可以點開來卡位
                        if !point.isCounting {
                            self.slottingPoint = point
                            self.isSlottingSheetPresented = true
                        }
                    }
            }
        }
        .listStyle(PlainListStyle())
    }

    // MARK: - 單一花田卡片列
    private func flowerCardRow(for p: FlowerStationPoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // 編號 Badge
                Text(p.displayBadgeNumber)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(p.isCounting ? Color.red : Color.green)
                    .cornerRadius(6)

                Text(p.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                if let s = p.seedlings, s > 0 {
                    Text("\(s) 苗")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(4)
                }

                Spacer()

                if p.isCounting {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 12))
                        Text(p.remainingFormatted)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.red)
                } else {
                    Text("待命中")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.green)
                }
            }

            // 備註與卡位者 (僅在冷卻中顯示，待命時自動清空不顯示)
            HStack(spacing: 12) {
                if p.isCounting && !p.planter.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                        Text(p.planter)
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.secondary)
                }

                if p.isCounting && !p.remark.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text")
                            .font(.system(size: 11))
                        Text(p.remark)
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()

                // 快捷按鈕
                HStack(spacing: 8) {
                    if let coord = p.coordinate {
                        Button(action: {
                            session.teleport(to: coord, label: p.name)
                            dismiss()
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 10))
                                Text("瞬移")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 卡位與開跑彈窗 (預填暱稱，備註選填)
    private func slotActionSheet(for p: FlowerStationPoint) -> some View {
        NavigationView {
            Form {
                Section(header: Text("花田資訊")) {
                    HStack {
                        Text("名稱")
                        Spacer()
                        Text(p.name).bold()
                    }
                    if let s = p.seedlings, s > 0 {
                        HStack {
                            Text("苗數")
                            Spacer()
                            Text("\(s) 苗")
                        }
                    }
                    HStack {
                        Text("狀態")
                        Spacer()
                        Text(p.isCounting ? "冷卻中 (剩餘 \(p.remainingFormatted))" : "空間待命")
                            .foregroundColor(p.isCounting ? .red : .green)
                            .bold()
                    }
                }

                Section(header: Text("卡位設定 (已自動預填您的帳號暱稱)")) {
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundColor(.blue)
                        TextField("種花者暱稱", text: $inputNickname)
                    }

                    HStack {
                        Image(systemName: "square.and.pencil")
                            .foregroundColor(.secondary)
                        TextField("備註說明 (選填，如花種/時間)", text: $inputRemark)
                    }
                }

                Section(header: Text("預計使用路線 (單一推薦・可更正記憶)")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            if !selectedRouteName.isEmpty {
                                Text(selectedRouteName)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.primary)
                                if let pref = station.getPreferredRouteName(for: p.name), pref == selectedRouteName {
                                    Text("使用者指定記憶路線")
                                        .font(.caption2)
                                        .foregroundColor(.purple)
                                } else {
                                    Text("系統最佳推薦路線")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            } else {
                                Text("資料庫無匹配路線 (開跑將瞬移至中心)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Menu {
                            Section(header: Text("更正使用路線 (自動記憶)")) {
                                ForEach(station.findMatchingRoutes(for: p)) { item in
                                    Button(action: {
                                        selectedRouteName = item.route.name
                                        station.setPreferredRouteName(item.route.name, for: p.name)
                                        session.showToast("已更正並記住【\(p.name)】使用路線為【\(item.route.name)】")
                                    }) {
                                        HStack {
                                            Text(item.route.name)
                                            if item.isHarvestRecommended {
                                                Text("（推薦）")
                                            }
                                        }
                                    }
                                }
                                Divider()
                                ForEach(SavedDatabaseStore.shared.savedRoutes) { r in
                                    Button(action: {
                                        selectedRouteName = r.name
                                        station.setPreferredRouteName(r.name, for: p.name)
                                        session.showToast("已更正並記住【\(p.name)】使用路線為【\(r.name)】")
                                    }) {
                                        Text(r.name)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "pencil.circle.fill")
                                Text("更正")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(6)
                        }
                    }
                }

                Section {
                    // 1. 瞬移至此
                    if let coord = p.coordinate {
                        Button(action: {
                            session.teleport(to: coord, label: p.name)
                            isSlottingSheetPresented = false
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "location.fill")
                                    .foregroundColor(.blue)
                                Text("瞬移至此花田")
                                    .foregroundColor(.primary)
                            }
                        }
                    }

                    // 2. 一鍵卡位
                    Button(action: {
                        submitSlotting(point: p, startCruise: false)
                    }) {
                        HStack {
                            Image(systemName: "person.badge.shield.checkmark.fill")
                                .foregroundColor(.green)
                            Text(isSubmittingSlot ? "正在卡位..." : "一鍵卡位 (保留花田)")
                                .foregroundColor(.green)
                                .bold()
                        }
                    }
                    .disabled(isSubmittingSlot)

                    // 3. 一鍵卡位並自動開跑巡航
                    Button(action: {
                        submitSlotting(point: p, startCruise: true)
                    }) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(.orange)
                            Text(isSubmittingSlot ? "正在處理..." : "一鍵卡位並開跑巡航")
                                .foregroundColor(.orange)
                                .bold()
                        }
                    }
                    .disabled(isSubmittingSlot)
                }
            }
            .navigationTitle(p.name)
            .navigationBarItems(trailing: Button("關閉") { isSlottingSheetPresented = false })
            .onAppear {
                let name = station.stationDisplayName
                self.inputNickname = !name.isEmpty ? name : station.stationEmail
                self.inputRemark = ""
                let matches = station.findMatchingRoutes(for: p)
                let pref = station.getPreferredRouteName(for: p.name)
                let best = matches.first(where: { $0.route.name == pref }) ?? matches.first
                self.selectedRouteName = best?.route.name ?? (pref ?? "")
            }
        }
    }

    private func submitSlotting(point: FlowerStationPoint, startCruise: Bool) {
        guard !inputNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            session.showToast("請輸入卡位暱稱")
            return
        }

        isSubmittingSlot = true
        let nickname = inputNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let remark = inputRemark.trimmingCharacters(in: .whitespacesAndNewlines)

        station.occupySpot(pointIndex: point.index, pointName: point.name, planterNickname: nickname, durationHours: 23.0, isHidden: false, remark: remark) { success, msg in
            isSubmittingSlot = false
            if success {
                session.showToast("已成功卡位【\(point.name)】！")
                isSlottingSheetPresented = false

                if startCruise {
                    if !self.selectedRouteName.isEmpty,
                       let chosenRoute = SavedDatabaseStore.shared.savedRoutes.first(where: { $0.name == self.selectedRouteName }) {
                        self.station.setPreferredRouteName(chosenRoute.name, for: point.name)
                        // 以「繞圈種花」模式 (executionMode = 1) 啟動巡航
                        self.session.startFlowerRoute(
                            name: chosenRoute.name,
                            basePoints: chosenRoute.nodes,
                            loops: 0,
                            settings: self.session.flowerSettings
                        )
                        SavedDatabaseStore.shared.useRoute(name: chosenRoute.name)
                        self.session.showToast("已卡位並啟動【\(chosenRoute.name)】繞圈種花巡航！")
                    } else if let coord = point.coordinate {
                        self.session.teleport(to: coord, label: point.name)
                        SavedDatabaseStore.shared.addTeleportHistory(
                            lat: coord.latitude,
                            lng: coord.longitude,
                            label: "觀測站【\(point.name)】"
                        )
                        self.session.showToast("已卡位並瞬移至【\(point.name)】花田中心")
                    }
                    dismiss()
                }
            } else {
                session.showToast("卡位失敗：\(msg ?? "連線逾時")")
            }
        }
    }
}
