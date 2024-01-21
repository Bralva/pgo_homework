\set r random(1, 6000000) 
SELECT id, fkRide, fio, contact, fkSeat FROM book.tickets WHERE id = :r;