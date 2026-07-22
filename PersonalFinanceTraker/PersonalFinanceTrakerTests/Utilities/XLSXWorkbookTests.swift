import Testing
import Foundation
@testable import PersonalFinanceTraker

struct XLSXWorkbookTests {

    // Minimal hand-built, pre-verified .xlsx fixtures (see plan doc for how they
    // were generated and validated). Written to a temp file per test because
    // XLSXWorkbook.read(from:) takes a URL.
    static let sampleXLSXBase64 = """
    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
    """

    static let multiSheetXLSXBase64 = """
    UEsDBBQAAAAIALqu9Fw3p7O+IwEAAM8DAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbMWTy2oCMRSG9z5FyFZM1EUpZWZc9LJsC7UP
    cJqccYK5kROtvn3j2BuligWhqxDOf/lIONVs4yxbYyITfM0nYswZehW08YuaP8/vRpecUQavwQaPNd8i8VkzqObbiMSK2VPNu5zj
    lZSkOnRAIkT0ZdKG5CCXa1rICGoJC5TT8fhCquAz+jzKuwzeDBirbrCFlc3sdlMme5aElji73mt3dTWHGK1RkMtcrr3+UTR6LxHF
    2WuoM5GGRcDloZLd8HDHl/WhPFEyGtkjpHwPrgjlxsrXkJYvISzF8ZxfWEPbGoU6qJUrFkExIWjqELOzoj+FA+OHJyH0epL9MTkz
    y2f+31Gm/4dCeWuRzv0tfegJ5R0k1E85lSU6O8P37A+USvbr2AzeAFBLAwQUAAAACAC6rvRcXd8jJ7QAAAAtAQAACwAAAF9yZWxz
    Ly5yZWxzjc+/DoIwEAbwnadobpeCgzGGwmJMWA0+QC3Hn1B6TVsV3t6OYhwcL3ff7/IV1TJr9kTnRzIC8jQDhkZRO5pewK257I7A
    fJCmlZoMCljRQ1UmxRW1DDHjh9F6FhHjBQwh2BPnXg04S5+SRRM3HblZhji6nlupJtkj32fZgbtPA8qEsQ3L6laAq9scWLNa/Ien
    rhsVnkk9ZjThx5eviyhL12MQsGj+IjfdiaY0osBjR74pWSZvUEsDBBQAAAAIALqu9FxHUYgmzgAAAFYBAAAPAAAAeGwvd29ya2Jv
    b2sueG1sjVC7bsMwDNz9FQL3Ro6HojBkZykCpHP7AYpFx0Is0iDV199XjWEgQ4duPPJ4d6Q7fKXZfKBoZOpgv6vBIA0cIl06eHs9
    PjyB0ewp+JkJO/hGhUNfuU+W65n5aso+aQdTzktrrQ4TJq87XpDKZGRJPhcoF6uLoA86IeY026auH23ykWBVaOU/GjyOccBnHt4T
    Ul5FBGefS3qd4qLQV8a4m4n+lhsw5FNJ/+KL361xCuVaMNLGUsgp7MH+wT/i+Y7f3PGble/s5uXs9pK++gFQSwMEFAAAAAgAuq70
    XJSM7QXlAAAA0AIAABoAAAB4bC9fcmVscy93b3JrYm9vay54bWwucmVsc72SzWrDMAyA73kKo/viJBtjjDi9lEGvW/cAxlbi0MQ2
    lvaTt5/ZWElhozuUnYQk9OkDqd28z5N4xURj8ArqsgKB3gQ7+kHB8/7h6g4EsfZWT8GjggUJNl3RPuKkOc+QGyOJDPGkwDHHeynJ
    OJw1lSGiz50+pFlzTtMgozYHPaBsqupWpjUDukKIE6zYWQVpZ2sQ+yXiX/Ch70eD22BeZvT8wxb5FtKBHCJnqE4DsoJjieRnqMtM
    BfmrT/PPPs0Zn+tL+hAvUz7xUeYrP2Nwc1EDpxPaJ075Bdci6/K3TytP/rArPgBQSwMEFAAAAAgAuq70XANZnh8qAQAASgIAAA0A
    AAB4bC9zdHlsZXMueG1slZLBbsMgDIbvfQrEfaXdYZqmhB4mRdq5nbQrTZwECUwEbtXu6WdCurXHnfz7B3/GQLW7eCfOEJMNWMvt
    eiMFYBs6i0MtPw/N06sUiQx2xgWEWl4hyZ1eVYmuDvYjAAkmYKrlSDS9KZXaEbxJ6zAB8kofojfEaRxUmiKYLuUi79TzZvOivLEo
    9UqIqg9ISbThhMTnkHo2dJW+xdk4drZS6QqNh5K/G2eP0WZTlZ1zSIVlnXtksaGryRBBxIYTsejDdeKhkEcrpHnfHArpGGLHl3PP
    KpauHPTENdEOY44UJpUXiYJn0VkzBDQuU28ViyjkFpzb50v86h/wl17gyTeePrpa8mvkqW6Sj7XIQipJbnFP+8U/ktll//94celv
    fTJYLWT+A+rvE+jVD1BLAwQUAAAACAC6rvRcpyUBvq4AAAAQAQAAFAAAAHhsL3NoYXJlZFN0cmluZ3MueG1sdY6xCgIxEET7+4qw
    veYUEZEkFoKFhZV+QLxbvcBlc2b3xPt704iNNgNvhgdjdq/YqydmDoksLOY1KKQmtYHuFi7nw2wDisVT6/tEaGFChp2rDLOoohJb
    6ESGrdbcdBg9z9OAVJZbytFLwXzXPGT0LXeIEnu9rOu1jj4QqCaNJBZWoEYKjxH3H3aVUoaDM+JOSdBocUYX/tZHT6PPU3krefqx
    /9EOeM2/vJIsrnoDUEsDBBQAAAAIALqu9Fw6qqQeswAAABQBAAAYAAAAeGwvd29ya3NoZWV0cy9zaGVldDEueG1sZY/BDoIwDEDv
    fMXSuxQ4GGO2GRPjF+gHLFCByDayLqh/7+JAMB6W9LV9bSdPbzuIiQL33iko8wIEudo3vWsV3G/X3QEER+MaM3hHCj7EcNKZfPnw
    5I4oijTAsYIuxvGIyHVH1nDuR3Kp8vDBmpgwtMhjINMskh2wKoo9WtM70JkQcklfTDQzJQ7+JUI6CLSs5+BcgogKOPGkC4mTllin
    l/p+jWo1qo1R/hkSNyslrv/R2RdQSwMEFAAAAAgAuq70XEoXgIKzAAAAFAEAABgAAAB4bC93b3Jrc2hlZXRzL3NoZWV0Mi54bWxl
    j1EKwjAMQP93ipJ/l62CiLQdgngCPUDZohuu7WjKpre3+iGKH4W8JC9JVXN3o5gp8hC8hrqsQJBvQzf4q4bz6bjaguBkfWfH4EnD
    gxgaU6glxBv3REnkAZ419ClNO0Rue3KWyzCRz5VLiM6mjPGKPEWy3VtyI8qq2qCzgwdTCKHe6YNN9kWZY1hEzAeBUe0r2NcgkgbO
    PBupcDYK2/xy368hP4b8MtZ/hsKvlQo//zHFE1BLAQIUAxQAAAAIALqu9Fw3p7O+IwEAAM8DAAATAAAAAAAAAAAAAACAAQAAAABb
    Q29udGVudF9UeXBlc10ueG1sUEsBAhQDFAAAAAgAuq70XF3fIye0AAAALQEAAAsAAAAAAAAAAAAAAIABVAEAAF9yZWxzLy5yZWxz
    UEsBAhQDFAAAAAgAuq70XEdRiCbOAAAAVgEAAA8AAAAAAAAAAAAAAIABMQIAAHhsL3dvcmtib29rLnhtbFBLAQIUAxQAAAAIALqu
    9FyUjO0F5QAAANACAAAaAAAAAAAAAAAAAACAASwDAAB4bC9fcmVscy93b3JrYm9vay54bWwucmVsc1BLAQIUAxQAAAAIALqu9FwD
    WZ4fKgEAAEoCAAANAAAAAAAAAAAAAACAAUkEAAB4bC9zdHlsZXMueG1sUEsBAhQDFAAAAAgAuq70XKclAb6uAAAAEAEAABQAAAAA
    AAAAAAAAAIABngUAAHhsL3NoYXJlZFN0cmluZ3MueG1sUEsBAhQDFAAAAAgAuq70XDqqpB6zAAAAFAEAABgAAAAAAAAAAAAAAIAB
    fgYAAHhsL3dvcmtzaGVldHMvc2hlZXQxLnhtbFBLAQIUAxQAAAAIALqu9FxKF4CCswAAABQBAAAYAAAAAAAAAAAAAACAAWcHAAB4
    bC93b3Jrc2hlZXRzL3NoZWV0Mi54bWxQSwUGAAAAAAgACAAIAgAAUAgAAAAA
    """

    static func writeTempFile(base64: String, name: String) -> URL {
        let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try! data.write(to: url)
        return url
    }

    @Test func readsSingleSheetName() throws {
        let url = Self.writeTempFile(base64: Self.sampleXLSXBase64, name: "sample-\(UUID()).xlsx")
        let workbook = try XLSXWorkbook.read(from: url)
        #expect(workbook.sheetNames == ["Transactions"])
    }

    @Test func readsMultipleSheetNames() throws {
        let url = Self.writeTempFile(base64: Self.multiSheetXLSXBase64, name: "multi-\(UUID()).xlsx")
        let workbook = try XLSXWorkbook.read(from: url)
        #expect(workbook.sheetNames == ["Jan", "Feb"])
    }

    @Test func corruptFileThrowsUnreadable() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt-\(UUID()).xlsx")
        try! "not a zip file".write(to: url, atomically: true, encoding: .utf8)
        #expect(throws: XLSXReadError.unreadable) {
            try XLSXWorkbook.read(from: url)
        }
    }

    @Test func convertsHeaderRowAndDataRows() throws {
        let url = Self.writeTempFile(base64: Self.sampleXLSXBase64, name: "sample-\(UUID()).xlsx")
        let workbook = try XLSXWorkbook.read(from: url)
        let file = try workbook.csvFile(forSheet: "Transactions")
        #expect(file.headers == ["Date", "Amount", "Note"])
        #expect(file.rowCount == 2)
    }

    @Test func convertsDateCellsToCanonicalISOStrings() throws {
        let url = Self.writeTempFile(base64: Self.sampleXLSXBase64, name: "sample-\(UUID()).xlsx")
        let workbook = try XLSXWorkbook.read(from: url)
        let file = try workbook.csvFile(forSheet: "Transactions")
        var dates: [String] = []
        file.processRows { row in dates.append(row[0]) }
        // Serials 46027 / 46096 verified against the Excel/OLE epoch (1899-12-30 + N days)
        #expect(dates == ["2026-01-05 00:00:00", "2026-03-15 00:00:00"])
    }

    @Test func convertsNumberAndStringCellsAsPlainText() throws {
        let url = Self.writeTempFile(base64: Self.sampleXLSXBase64, name: "sample-\(UUID()).xlsx")
        let workbook = try XLSXWorkbook.read(from: url)
        let file = try workbook.csvFile(forSheet: "Transactions")
        var amounts: [String] = []
        var notes: [String] = []
        file.processRows { row in
            amounts.append(row[1])
            notes.append(row[2])
        }
        #expect(amounts == ["-42.5", "1500"])
        #expect(notes == ["Groceries", "Salary"])
    }

    @Test func isDateNumberFormatMatchesBuiltInDateAndTimeIds() {
        #expect(XLSXWorkbook.isDateNumberFormat(14))
        #expect(XLSXWorkbook.isDateNumberFormat(22))
        #expect(XLSXWorkbook.isDateNumberFormat(46))
        #expect(!XLSXWorkbook.isDateNumberFormat(0))
        #expect(!XLSXWorkbook.isDateNumberFormat(9))
        #expect(!XLSXWorkbook.isDateNumberFormat(164))
    }
}
