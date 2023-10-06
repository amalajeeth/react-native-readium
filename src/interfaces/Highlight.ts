import { Locator } from "./Locator";

export interface Highlight {
    id: string;
    bookId: string;
    locator: Locator;
    color: number;
}