import java.util.ArrayList;

class GeneraNumeri {
    public static void main(String [] args) {
        ArrayList<String> lista = new ArrayList<>();
        for( int i =0; i<=Integer.parseInt(args[0]); i++) {
            String cf = "";
            do {
                cf = ((long) (Math.random() * 10000000000000000L)) + "";
            } while (lista.contains("('" + cf + "', "));
            lista.add("('" + cf + "', ");
        }
        lista.forEach( n -> System.out.println(n));
    }
}