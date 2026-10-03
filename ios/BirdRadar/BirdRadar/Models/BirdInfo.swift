import Foundation

struct BirdInfo: Codable {
    let species: String
    let description: String
    let imageURL: String?
    let wikiURL: String
    let ebirdURL: String
    let allaboutbirdsURL: String
    let scientificName: String
    let family: String
    let order: String

    enum CodingKeys: String, CodingKey {
        case species, description, family, order
        case imageURL = "image_url"
        case wikiURL = "wiki_url"
        case ebirdURL = "ebird_url"
        case allaboutbirdsURL = "allaboutbirds_url"
        case scientificName = "scientific_name"
    }
}
