package fi.helsinki.cs.maventest;

import com.google.inject.AbstractModule;
import com.google.inject.Guice;
import com.google.inject.Injector;

public class App {
    public static class Foo {
        public void doStuff() {
            System.out.println("Hello world");
        }
    }
    
    public static class FooModule extends AbstractModule {
        @Override
        protected void configure() {
            //bind(Foo.class).to(Foo.class);
        }
    }
    
    public static void main(String[] args) {
        Injector injector = Guice.createInjector(new FooModule());
        Foo foo = injector.getInstance(Foo.class);
        foo.doStuff();
    }
}
