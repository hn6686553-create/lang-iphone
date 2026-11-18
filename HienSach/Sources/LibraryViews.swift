import SwiftUI
import UniformTypeIdentifiers

enum Palette {
    static let paper=Color(bookHex:"#F4EEE2"), ink=Color(bookHex:"#302C25"), green=Color(bookHex:"#344C40"), muted=Color(bookHex:"#695D4C"), line=Color(bookHex:"#D9CDB9")
}
@main
struct HienSachApp:App {
    @StateObject private var shelf=Shelf()
    @Environment(\.scenePhase) private var phase
    var body:some Scene {
        WindowGroup {
            Home().environmentObject(shelf)
                .onOpenURL { if $0.isFileURL { shelf.importFiles([$0]) } }
                .onChange(of:phase) { _,value in if value != .active {shelf.flush()} }
        }
    }
}
struct Home:View {
    @EnvironmentObject var shelf:Shelf
    @State private var importer=false
    @State private var tab=0
    var body:some View {
        TabView(selection:$tab){
            Cabinet(importer:$importer).tabItem{Label("Tủ sách",systemImage:"books.vertical")}.tag(0)
            OnlineView().tabItem{Label("Trực tuyến",systemImage:"globe")}.tag(1)
            RibbonsView().tabItem{Label("Dấu trang",systemImage:"bookmark")}.tag(2)
        }
        .tint(Palette.green).preferredColorScheme(.light)
        .toolbarBackground(Palette.paper,for:.tabBar)
        .fileImporter(isPresented:$importer,allowedContentTypes:[UTType(filenameExtension:"epub") ?? .data,.pdf,.plainText],allowsMultipleSelection:true) { result in
            switch result{
            case .success(let urls):shelf.importFiles(urls)
            case .failure(let e):if (e as NSError).code != NSUserCancelledError{shelf.notice=ShelfNotice(text:e.localizedDescription)}
            }
        }
        .fullScreenCover(item:$shelf.reading){ item in
            if let book=shelf.book(item.id){ReaderView(book:book,start:item.spot).environmentObject(shelf)}
        }
        .alert(item:$shelf.notice){Alert(title:Text("Hiên Sách"),message:Text($0.text),dismissButton:.default(Text("Đóng")))}
        .task{shelf.bootstrap()}
    }
}
struct Bookplate: View {
    var body:some View {
        HStack(spacing:8){Image(systemName:"book.pages").font(.system(size:17));Text("Hiên Sách").italic().font(.system(size:20,design:.serif))}
            .foregroundStyle(Palette.green).accessibilityElement(children:.combine)
    }
}
struct ShelfHeader: View {
    let title:String
    var body:some View {
        Text(title).font(.system(size:39,weight:.medium,design:.serif)).foregroundStyle(Palette.ink).frame(maxWidth:.infinity,alignment:.leading).accessibilityAddTraits(.isHeader)
    }
}
private let coverCache=NSCache<NSString,UIImage>()
struct BookCover:View {
    let book:Book
    let folder:URL
    var body:some View {
        GeometryReader{g in
            ZStack(alignment:.leading){
                if let image=cover() {
                    Image(uiImage:image).resizable().scaledToFill().frame(width:g.size.width,height:g.size.height).clipped()
                } else {
                    let tones=["#4B6250","#79513F","#48586B","#776334","#684649"]
                    let n=Int(book.id.prefix(2),radix:16) ?? 0
                    ZStack{
                        Color(bookHex:tones[n%tones.count]);Rectangle().strokeBorder(Color(bookHex:"#D7C79D").opacity(0.68),lineWidth:1).padding(7)
                        VStack(spacing:8){
                            Image(systemName:"book.closed").font(.system(size:g.size.width*0.18,weight:.thin))
                            Text(book.title).font(.system(size:max(12,g.size.width*0.15),weight:.medium,design:.serif)).multilineTextAlignment(.center).lineLimit(4).minimumScaleFactor(0.6)
                            if !book.author.isEmpty { Text(book.author).font(.caption2).lineLimit(1) }
                        }.padding(10).foregroundStyle(Color(bookHex:"#F5E9C9"))
                    }
                }
                LinearGradient(stops:[.init(color:.black.opacity(0.25),location:0),.init(color:.white.opacity(0.13),location:0.35),.init(color:.black.opacity(0.2),location:0.57),.init(color:.clear,location:1)],startPoint:.leading,endPoint:.trailing).frame(width:max(5,g.size.width*0.085))
            }.clipShape(RoundedRectangle(cornerRadius:3)).shadow(color:.black.opacity(0.27),radius:3,x:2,y:2)
        }.aspectRatio(0.69,contentMode:.fit).accessibilityHidden(true)
    }
    private func cover()->UIImage?{
        guard let cover=book.cover else{return nil}
        let key=book.id as NSString
        if let image=coverCache.object(forKey:key){return image}
        guard let image=UIImage(contentsOfFile:folder.appendingPathComponent(cover).path) else{return nil}
        coverCache.countLimit=100;coverCache.setObject(image,forKey:key);return image
    }
}
struct WoodenLedge:View {
    var body:some View{
        VStack(spacing:0){
            LinearGradient(colors:[Color(bookHex:"#C49A71"),Color(bookHex:"#E2BD92")],startPoint:.top,endPoint:.bottom).frame(height:4)
            Image("Walnut").resizable().frame(height:10).overlay(alignment:.bottom){Rectangle().fill(.black.opacity(0.20)).frame(height:1)}
        }.clipShape(RoundedRectangle(cornerRadius:2)).shadow(color:.brown.opacity(0.30),radius:4,x:0,y:5).accessibilityHidden(true)
    }
}
enum CabinetFilter:String,CaseIterable {case all="Tất cả",unfinished="Đang đọc",finished="Đã đọc"}
struct Cabinet:View {
    @EnvironmentObject var shelf:Shelf
    @Environment(\.horizontalSizeClass) var sizeClass
    @Binding var importer:Bool
    @State private var filter:CabinetFilter = .all
    @State private var search=false
    @State private var query=""
    @State private var removing:Book?
    private var visible:[Book]{
        shelf.books.filter{b in
            (filter == .all || (filter == .finished ? b.finished : b.opened != nil && !b.finished)) && (query.isEmpty || (b.title+" "+b.author).localizedStandardContains(query))
        }
    }
    private var recent:Book?{shelf.books.filter{$0.opened != nil && !$0.finished}.max{($0.opened ?? .distantPast)<($1.opened ?? .distantPast)}}
    var body:some View{
        ScrollView{
            VStack(alignment:.leading,spacing:0){
                HStack{
                    Bookplate();Spacer()
                    Button{withAnimation{search.toggle();if !search{query=""}}}label:{Image(systemName:"magnifyingglass").frame(width:42,height:42)}.accessibilityLabel("Tìm trong tủ sách")
                    Button{importer=true}label:{Image(systemName:"plus").fontWeight(.medium).frame(width:42,height:42).background(Palette.green,in:Circle()).foregroundStyle(.white)}.accessibilityLabel("Nhập sách từ Tệp")
                }.padding(.bottom,14)
                HStack(alignment:.firstTextBaseline){ShelfHeader(title:"Tủ sách");Text("\(shelf.books.count) cuốn").font(.subheadline).foregroundStyle(Palette.muted).fixedSize()}.padding(.bottom,18)
                if search{TextField("Tìm tên sách hoặc tác giả",text:$query).textFieldStyle(.roundedBorder).padding(.bottom,12)}
                if let b=recent ?? shelf.books.first,filter == .all,query.isEmpty {
                    Button{shelf.open(b.id)}label:{
                        HStack(spacing:15){
                            BookCover(book:b,folder:shelf.folder(b.id)).frame(width:50)
                            VStack(alignment:.leading,spacing:4){
                                Label(b.opened == nil ? "Mở cuốn đầu tiên":"Đọc tiếp",systemImage:b.opened == nil ? "book":"bookmark.fill").font(.caption.weight(.semibold)).foregroundStyle(Color(bookHex:"#846038"))
                                Text(b.title).font(.system(size:22,weight:.medium,design:.serif)).foregroundStyle(Palette.ink).lineLimit(1)
                                Text(b.label(at:b.spot)).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                            }
                            Spacer();Image(systemName:"arrow.right").foregroundStyle(Palette.green)
                        }.padding(14).background(Color(bookHex:"#EAE2D1"),in:RoundedRectangle(cornerRadius:12))
                    }.buttonStyle(.plain).padding(.bottom,18).accessibilityIdentifier("continue")
                }
                HStack(spacing:5){
                    ForEach(CabinetFilter.allCases,id:\.self){item in
                        Button{withAnimation(.easeInOut(duration:0.16)){filter=item}}label:{
                            Text(item.rawValue).font(.subheadline.weight(filter == item ? .semibold:.regular)).padding(.vertical,8).padding(.horizontal,13)
                                .foregroundStyle(filter == item ? .white:Palette.muted).background(filter == item ? Palette.green:Color.clear,in:Capsule())
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                }.padding(.bottom,26)
                if visible.isEmpty {
                    if shelf.busy{ProgressView("Đang xếp sách lên kệ…").frame(maxWidth:.infinity).padding(.vertical,48)}
                    else{
                        ContentUnavailableView(query.isEmpty ? (filter == .all ? "Kệ còn trống" : filter.rawValue == "Đang đọc" ? "Chưa có sách đang đọc":"Chưa có sách đã đọc"):"Chưa tìm thấy sách",systemImage:"books.vertical",description:Text(filter == .all && query.isEmpty ? "Chạm dấu cộng để nhập sách từ Tệp.":""))
                    }
                } else{
                    let columns=sizeClass == .regular ? 5:3
                    let values=visible
                    ForEach(0..<((values.count+columns-1)/columns),id:\.self){row in
                        let books=Array(values.dropFirst(row*columns).prefix(columns))
                        VStack(spacing:0){
                            HStack(alignment:.bottom,spacing:13){
                                ForEach(0..<columns,id:\.self){i in
                                    if i<books.count{
                                        let b=books[i]
                                        Button{shelf.open(b.id)}label:{BookCover(book:b,folder:shelf.folder(b.id))}
                                            .buttonStyle(.plain).accessibilityLabel(b.title).accessibilityIdentifier("cover-"+b.title)
                                            .contextMenu{
                                                Button(b.finished ? "Đánh dấu chưa đọc xong":"Đánh dấu đã đọc"){shelf.finish(b.id,!b.finished)}
                                                Button("Gỡ khỏi tủ sách",role:.destructive){removing=b}
                                            }
                                    }else{Color.clear.aspectRatio(0.69,contentMode:.fit).accessibilityHidden(true)}
                                }
                            }.padding(.horizontal,10)
                            WoodenLedge()
                            HStack(alignment:.top,spacing:13){
                                ForEach(0..<columns,id:\.self){i in
                                    Group{if i<books.count{
                                        let b=books[i]
                                        Button{shelf.open(b.id)}label:{
                                            VStack(alignment:.leading,spacing:3){
                                                Text(b.title).font(.system(size:14,weight:.semibold,design:.serif)).foregroundStyle(Palette.ink).lineLimit(2)
                                                Text(b.finished ? "Đã đọc" : b.kind.rawValue).font(.caption2).foregroundStyle(Palette.muted)
                                            }.frame(maxWidth:.infinity,alignment:.leading)
                                        }.buttonStyle(.plain)
                                    }else{Color.clear.frame(maxWidth:.infinity)}}.frame(maxWidth:.infinity,alignment:.leading)
                                }
                            }.padding(.horizontal,9).padding(.top,9)
                        }.padding(.bottom,26)
                    }
                }
            }.padding(.horizontal,20).padding(.top,12).frame(maxWidth:780)
        }.frame(maxWidth:.infinity).background(Palette.paper).foregroundStyle(Palette.ink)
        .confirmationDialog("Gỡ “\(removing?.title ?? "")” khỏi tủ sách?",isPresented:Binding(get:{removing != nil},set:{if !$0{removing=nil}}),titleVisibility:.visible,presenting:removing){b in Button("Gỡ sách",role:.destructive){shelf.remove(b.id)}}
    }
}
struct RibbonsView:View {
    @EnvironmentObject var shelf:Shelf
    var body:some View{
        ScrollView{
            VStack(alignment:.leading,spacing:18){
                Bookplate();ShelfHeader(title:"Dấu trang")
                if shelf.books.allSatisfy({$0.ribbons.isEmpty}) {
                    ContentUnavailableView("Chưa có dấu trang",systemImage:"bookmark",description:Text("Khi đọc, chạm biểu tượng dải ruy băng để giữ lại một trang.")).frame(maxWidth:.infinity).padding(.top,55)
                }
                ForEach(shelf.books.filter{!$0.ribbons.isEmpty}){b in
                    VStack(alignment:.leading,spacing:0){
                        Text(b.title).font(.title3.weight(.medium)).padding(.bottom,8)
                        ForEach(b.ribbons.sorted{$0.date>$1.date}){mark in
                            HStack{
                                Button{shelf.open(b.id,at:mark.spot)}label:{Label(mark.label,systemImage:"bookmark.fill").frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,13)}
                                Button{shelf.removeRibbon(b.id,mark.id)}label:{Image(systemName:"xmark.circle").padding(6)}.accessibilityLabel("Xóa dấu trang")
                            };Divider()
                        }
                    }
                }
            }.foregroundStyle(Palette.ink).padding(20).frame(maxWidth:720)
        }.frame(maxWidth:.infinity).background(Palette.paper)
    }
}
