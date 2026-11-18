import Foundation
import PDFKit

struct Passage:Identifiable {
    let unit:Int
    let title:String
    let excerpt:String
    let query:String
    var id:Int{unit}
}
enum FindInBook {
    static func passages(in book:Book,folder:URL,query:String) throws->[Passage]{
        let term=query.clean
        guard term.count>=2 else{return []}
        let pdf=book.kind == .pdf ? PDFDocument(url:folder.appendingPathComponent("document.pdf")):nil
        let tags=try NSRegularExpression(pattern:"(?is)<(head|script|style)\\b[^>]*>.*?</\\1\\s*>|<[^>]+>")
        var matches=[Passage]()
        for unit in 0..<book.units {
            try Task.checkCancellation()
            let plain:String
            if let pdf{plain=pdf.page(at:unit)?.string ?? ""}
            else if book.chapters.indices.contains(unit){
                let file=folder.appendingPathComponent("content").appendingPathComponent(book.chapters[unit].file)
                guard let bytes=try? file.resourceValues(forKeys:[.fileSizeKey]).fileSize,bytes<=12_000_000,
                      let html=try? String(contentsOf:file,encoding:.utf8) else{continue}
                plain=tags.stringByReplacingMatches(in:html,range:NSRange(html.startIndex...,in:html),withTemplate:" ")
                    .replacingOccurrences(of:"&amp;",with:"&").replacingOccurrences(of:"&nbsp;",with:" ").replacingOccurrences(of:"&quot;",with:"\"")
            }else{continue}
            let str=plain.replacingOccurrences(of:"\\s+",with:" ",options:.regularExpression)
            guard let range=str.range(of:term,options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"vi")) else{continue}
            let low=str.index(range.lowerBound,offsetBy:-26,limitedBy:str.startIndex) ?? str.startIndex
            let high=str.index(range.upperBound,offsetBy:75,limitedBy:str.endIndex) ?? str.endIndex
            let excerpt=(low==str.startIndex ? "":"…")+String(str[low..<high])+(high==str.endIndex ? "":"…")
            matches.append(Passage(unit:unit,title:book.label(at:.init(unit:unit)),excerpt:String(excerpt).clean,query:term))
            if matches.count==50{break}
        }
        return matches
    }
}
