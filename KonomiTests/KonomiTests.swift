import Foundation
import Testing
@testable import Konomi

struct KonomiTests {
    @Test func goodreadsCSVParserHandlesQuotedFields() throws {
        let csv = """
        Book Id,Title,Author,ISBN,ISBN13,My Rating,Average Rating,Year Published,Date Read,Date Added,Bookshelves,Exclusive Shelf,My Review,Private Notes
        1,"The Left Hand of Darkness","Ursula K. Le Guin",,9780441478125,5,4.1,1969,2024/02/03,2024/01/15,"favorites, sci-fi",read,"Loved the politics, and the ice.","Re-read soon"
        """

        let books = try GoodreadsImportService.parseCSV(data: Data(csv.utf8))

        #expect(books.count == 1)
        #expect(books[0].title == "The Left Hand of Darkness")
        #expect(books[0].author == "Ursula K. Le Guin")
        #expect(books[0].isbn13 == "9780441478125")
        #expect(books[0].myRating == 5)
        #expect(books[0].bookshelves == ["favorites", "sci-fi"])
        #expect(books[0].myReview == "Loved the politics, and the ice.")
        #expect(books[0].privateNotes == "Re-read soon")
    }

    @Test func goodreadsCSVParserRejectsWrongHeaders() throws {
        let csv = """
        Title,Author
        Test Book,Test Author
        """

        #expect(throws: GoodreadsImportError.self) {
            try GoodreadsImportService.parseCSV(data: Data(csv.utf8))
        }
    }
}
