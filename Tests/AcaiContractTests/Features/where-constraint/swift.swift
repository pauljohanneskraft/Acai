public protocol Named {}
public protocol Ranked {}

public class Shelf<Item> where Item: Named, Item: Ranked {
    public func put(item: Item) -> Int { 0 }
}
